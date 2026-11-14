import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A colour, 0..255 each.
typedef Rgb = ({int r, int g, int b});

/// One light (a strip, a lamp, the RGB of a computer) that follows the
/// music. [frame] is called up to 30 times a second; each kind sends what
/// it can take.
abstract class LightDevice {
  /// What it is, for settings: 'wled', 'govee', 'openrgb'.
  String get kind;

  /// Address as the user gave it ("192.168.1.40", "127.0.0.1:6742").
  String get address;

  /// Shown under its name: connected, how many LEDs, or what went wrong.
  String get status;

  Future<void> open();

  /// [color] at [level] (0..1); [beat] is true on the frame a beat lands.
  void frame(Rgb color, double level, {required bool beat});

  Future<void> close();

  Map<String, Object> toJson() => {'kind': kind, 'address': address};

  static LightDevice? fromJson(Map<String, dynamic> j) {
    final address = j['address'] as String? ?? '';
    return switch (j['kind']) {
      'wled' => WledDevice(address),
      'govee' => GoveeDevice(address),
      'openrgb' => OpenRgbDevice(address),
      _ => null,
    };
  }
}

Rgb _scale(Rgb c, double level) => (
  r: (c.r * level).round().clamp(0, 255),
  g: (c.g * level).round().clamp(0, 255),
  b: (c.b * level).round().clamp(0, 255),
);

/// WLED (ESP8266/ESP32 LED strips): every frame over UDP, its "realtime"
/// protocol. After two seconds without frames it goes back to its own
/// effect by itself.
class WledDevice implements LightDevice {
  WledDevice(this.address, {this.httpPort = 80, this.udpPort = 21324});

  /// Ports (other than WLED's own only in tests).
  final int httpPort, udpPort;

  @override
  final String address;
  @override
  String get kind => 'wled';
  @override
  String status = '';

  RawDatagramSocket? _socket;
  InternetAddress? _host;
  int _leds = 0;

  @override
  Future<void> open() async {
    try {
      _host = (await InternetAddress.lookup(address)).first;
      // How many LEDs: its JSON API.
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      try {
        final req = await client.getUrl(
          Uri.parse('http://$address:$httpPort/json/info'),
        );
        final res = await req.close().timeout(const Duration(seconds: 3));
        final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
        _leds = ((j['leds'] as Map?)?['count'] as num?)?.toInt() ?? 0;
      } finally {
        client.close();
      }
      if (_leds <= 0) throw const FormatException('no LEDs');
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      status = '$_leds LED';
    } catch (e) {
      status = 'error:$e';
    }
  }

  /// Realtime packets: DNRGB (start index, then colours), 489 LEDs each.
  static List<Uint8List> packets(int leds, Rgb c) {
    const perPacket = 489;
    final out = <Uint8List>[];
    for (var start = 0; start < leds; start += perPacket) {
      final n = (leds - start).clamp(0, perPacket);
      final p = Uint8List(4 + n * 3);
      p[0] = 4; // DNRGB
      p[1] = 2; // back to its own effect 2 s after the last frame
      p[2] = start >> 8;
      p[3] = start & 0xff;
      for (var i = 0; i < n; i++) {
        p[4 + i * 3] = c.r;
        p[5 + i * 3] = c.g;
        p[6 + i * 3] = c.b;
      }
      out.add(p);
    }
    return out;
  }

  @override
  void frame(Rgb color, double level, {required bool beat}) {
    final s = _socket, h = _host;
    if (s == null || h == null) return;
    for (final p in packets(_leds, _scale(color, level))) {
      s.send(p, h, udpPort);
    }
  }

  @override
  Future<void> close() async {
    _socket?.close();
    _socket = null;
  }

  @override
  Map<String, Object> toJson() => {'kind': kind, 'address': address};
}

/// Govee lamps and strips with "LAN control" on (in the Govee app): a
/// colour on each beat (they can't take 30 a second).
class GoveeDevice implements LightDevice {
  GoveeDevice(this.address, {this.port = 4003});

  /// Its control port (another only in tests).
  final int port;

  @override
  final String address;
  @override
  String get kind => 'govee';
  @override
  String status = '';

  RawDatagramSocket? _socket;
  InternetAddress? _host;
  final _since = Stopwatch();
  Rgb? _last;

  static Uint8List command(String cmd, Map<String, Object> data) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'msg': {'cmd': cmd, 'data': data},
          }),
        ),
      );

  @override
  Future<void> open() async {
    try {
      _host = (await InternetAddress.lookup(address)).first;
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.send(command('turn', {'value': 1}), _host!, port);
      _socket!.send(command('brightness', {'value': 100}), _host!, port);
      _since.start();
      status = 'ok';
    } catch (e) {
      status = 'error:$e';
    }
  }

  @override
  void frame(Rgb color, double level, {required bool beat}) {
    final s = _socket, h = _host;
    if (s == null || h == null) return;
    // On each beat, plus a resting colour now and then between.
    final c = _scale(color, level);
    if (!beat && _since.elapsedMilliseconds < 400) return;
    if (!beat && c == _last) return;
    _since
      ..reset()
      ..start();
    _last = c;
    s.send(
      command('colorwc', {
        'color': {'r': c.r, 'g': c.g, 'b': c.b},
        'colorTemInKelvin': 0,
      }),
      h,
      port,
    );
  }

  @override
  Future<void> close() async {
    _socket?.close();
    _socket = null;
  }

  @override
  Map<String, Object> toJson() => {'kind': kind, 'address': address};

  /// Govee devices on this network that answer a scan (2 s).
  static Future<List<String>> scan() async {
    final found = <String>{};
    RawDatagramSocket? listen, ask;
    try {
      listen = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        4002,
        reuseAddress: true,
      );
      listen.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = listen!.receive();
        if (d == null) return;
        try {
          final j = jsonDecode(utf8.decode(d.data)) as Map;
          final ip = ((j['msg'] as Map?)?['data'] as Map?)?['ip'] as String?;
          found.add(ip ?? d.address.address);
        } catch (_) {}
      });
      ask = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      ask.send(
        command('scan', {'account_topic': 'reserve'}),
        InternetAddress('239.255.255.250'),
        4001,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      listen?.close();
      ask?.close();
    }
    return found.toList();
  }
}

/// OpenRGB (keyboards, mice, fans, RAM, PC strips of most brands): its
/// SDK server, which the user turns on in OpenRGB (port 6742).
class OpenRgbDevice implements LightDevice {
  OpenRgbDevice(this.address);

  @override
  final String address;
  @override
  String get kind => 'openrgb';
  @override
  String status = '';

  Socket? _socket;

  /// LED count of each controller (keyboard, mouse…).
  final _leds = <int>[];
  final _buffer = BytesBuilder();
  final _waiting = <Completer<Uint8List>>[];

  static const _count = 0, _data = 1, _name = 50;
  static const _updateLeds = 1050, _customMode = 1100;

  static Uint8List packet(int device, int id, [List<int> data = const []]) {
    final b = BytesBuilder()
      ..add(ascii.encode('ORGB'))
      ..add(_u32(device))
      ..add(_u32(id))
      ..add(_u32(data.length))
      ..add(data);
    return b.toBytes();
  }

  static Uint8List _u32(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  /// The LEDs' colours of one controller: size, count, RGBA each.
  static Uint8List ledsPayload(int count, Rgb c) {
    final size = 4 + 2 + 4 * count;
    final d = ByteData(size)
      ..setUint32(0, size, Endian.little)
      ..setUint16(4, count, Endian.little);
    for (var i = 0; i < count; i++) {
      d
        ..setUint8(6 + i * 4, c.r)
        ..setUint8(7 + i * 4, c.g)
        ..setUint8(8 + i * 4, c.b);
    }
    return d.buffer.asUint8List();
  }

  @override
  Future<void> open() async {
    try {
      final parts = address.split(':');
      final host = parts.first.isEmpty ? '127.0.0.1' : parts.first;
      final port = parts.length > 1 ? int.parse(parts[1]) : 6742;
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _socket!.listen(_onData, onError: (_) {}, onDone: () => _socket = null);
      _socket!.add(packet(0, _name, [...utf8.encode('Segue'), 0]));
      _socket!.add(packet(0, _count));
      final count = (await _reply()).buffer.asByteData().getUint32(
        0,
        Endian.little,
      );
      _leds.clear();
      for (var i = 0; i < count; i++) {
        _socket!.add(packet(i, _data));
        _leds.add(controllerLeds(await _reply()));
        _socket!.add(packet(i, _customMode));
      }
      status = '$count RGB';
    } catch (e) {
      status = 'error:$e';
      _socket?.destroy();
      _socket = null;
    }
  }

  Future<Uint8List> _reply() {
    final c = Completer<Uint8List>();
    _waiting.add(c);
    return c.future.timeout(const Duration(seconds: 3));
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    var bytes = _buffer.toBytes();
    while (bytes.length >= 16) {
      final h = bytes.buffer.asByteData(bytes.offsetInBytes);
      final size = h.getUint32(12, Endian.little);
      if (bytes.length < 16 + size) break;
      final body = Uint8List.fromList(bytes.sublist(16, 16 + size));
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete(body);
      bytes = Uint8List.fromList(bytes.sublist(16 + size));
    }
    _buffer
      ..clear()
      ..add(bytes);
  }

  /// The number of LEDs in a controller's description (protocol 0).
  static int controllerLeds(Uint8List data) {
    final d = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes);
    var o = 4 + 4; // size, type
    int u16() {
      final v = d.getUint16(o, Endian.little);
      o += 2;
      return v;
    }

    int u32() {
      final v = d.getUint32(o, Endian.little);
      o += 4;
      return v;
    }

    void str() {
      final n = u16(); // read first: `o += u16()` would add to the old o
      o += n;
    }

    for (var i = 0; i < 5; i++) {
      str(); // name, description, version, serial, location
    }
    final modes = u16();
    o += 4; // active mode
    for (var m = 0; m < modes; m++) {
      str();
      o += 4 * 9; // value, flags, speed min/max, colours min/max, speed, direction, colour mode
      final colours = u16();
      o += 4 * colours;
    }
    final zones = u16();
    for (var z = 0; z < zones; z++) {
      str();
      o += 4 * 4; // type, leds min/max/count
      final matrix = u16();
      if (matrix > 0) {
        final h = u32(), w = u32();
        o += 4 * h * w;
      }
    }
    final leds = u16();
    for (var l = 0; l < leds; l++) {
      str();
      o += 4;
    }
    return u16(); // colours: one per LED
  }

  @override
  void frame(Rgb color, double level, {required bool beat}) {
    final s = _socket;
    if (s == null) return;
    final c = _scale(color, level);
    for (var i = 0; i < _leds.length; i++) {
      if (_leds[i] > 0) s.add(packet(i, _updateLeds, ledsPayload(_leds[i], c)));
    }
  }

  @override
  Future<void> close() async {
    await _socket?.close();
    _socket = null;
  }

  @override
  Map<String, Object> toJson() => {'kind': kind, 'address': address};
}
