import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/lights/light_devices.dart';
import 'package:segue/core/lights/light_sync.dart';

const _red = (r: 255, g: 0, b: 0);

/// A controller as OpenRGB describes it (protocol 0): [leds] LEDs.
Uint8List _controller(int leds) {
  final b = BytesBuilder();
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void str(String s) {
    u16(s.length + 1);
    b
      ..add(ascii.encode(s))
      ..addByte(0);
  }

  u32(0); // size (not read)
  u32(5); // type: keyboard
  for (final s in ['Keyboard', 'desc', '1.0', 'SN', 'HID']) {
    str(s);
  }
  u16(2); // modes
  u32(0); // active
  for (var m = 0; m < 2; m++) {
    str('Mode $m');
    for (var i = 0; i < 9; i++) {
      u32(i);
    }
    u16(2); // colours of the mode
    u32(0xff0000);
    u32(0x00ff00);
  }
  u16(1); // zones
  str('Keys');
  u32(1);
  u32(leds);
  u32(leds);
  u32(leds);
  u16(1); // a matrix
  u32(2);
  u32(3);
  for (var i = 0; i < 6; i++) {
    u32(i);
  }
  u16(leds);
  for (var i = 0; i < leds; i++) {
    str('Key $i');
    u32(i);
  }
  u16(leds);
  for (var i = 0; i < leds; i++) {
    u32(0);
  }
  return b.toBytes();
}

void main() {
  test('WLED: realtime frames over UDP, every LED', () async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((r) {
      r.response
        ..write(jsonEncode({'leds': {'count': 600}}))
        ..close();
    });
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = <Uint8List>[];
    udp.listen((e) {
      final d = udp.receive();
      if (d != null) got.add(d.data);
    });
    final wled = WledDevice(
      '127.0.0.1',
      httpPort: http.port,
      udpPort: udp.port,
    );
    await wled.open();
    expect(wled.status, '600 LED');
    wled.frame(_red, 0.5, beat: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(got.length, 2); // 489 + 111
    expect(got[0].sublist(0, 4), [4, 2, 0, 0]);
    expect(got[1].sublist(0, 4), [4, 2, 489 >> 8, 489 & 0xff]);
    expect(got[0].sublist(4, 7), [128, 0, 0]); // half brightness
    expect(got[1].length, 4 + 111 * 3);
    await wled.close();
    udp.close();
    await http.close(force: true);
  });

  test('Govee: a colour on the beat, as JSON', () async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = <Map>[];
    udp.listen((e) {
      final d = udp.receive();
      if (d != null) got.add(jsonDecode(utf8.decode(d.data)) as Map);
    });
    final g = GoveeDevice('127.0.0.1', port: udp.port);
    await g.open();
    g.frame(_red, 1, beat: true);
    g.frame(_red, 0.9, beat: false); // too soon: skipped
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final cmds = [for (final m in got) (m['msg'] as Map)['cmd']];
    expect(cmds, ['turn', 'brightness', 'colorwc']);
    final color = ((got.last['msg'] as Map)['data'] as Map)['color'] as Map;
    expect(color, {'r': 255, 'g': 0, 'b': 0});
    await g.close();
    udp.close();
  });

  test('OpenRGB: reads the controllers and sets every LED', () async {
    expect(OpenRgbDevice.controllerLeds(_controller(7)), 7);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final updates = <(int, int)>[]; // device, LED count
    final ids = <int>[];
    server.listen((client) {
      var buf = <int>[];
      client.listen((chunk) {
        buf.addAll(chunk);
        while (buf.length >= 16) {
          final h = Uint8List.fromList(buf.sublist(0, 16)).buffer.asByteData();
          final dev = h.getUint32(4, Endian.little);
          final id = h.getUint32(8, Endian.little);
          final size = h.getUint32(12, Endian.little);
          if (buf.length < 16 + size) break;
          final body = Uint8List.fromList(buf.sublist(16, 16 + size));
          buf = buf.sublist(16 + size);
          ids.add(id);
          if (id == 0) {
            client.add(OpenRgbDevice.packet(0, 0, Uint8List(4)..buffer.asByteData().setUint32(0, 2, Endian.little)));
          } else if (id == 1) {
            client.add(OpenRgbDevice.packet(dev, 1, _controller(dev == 0 ? 104 : 3)));
          } else if (id == 1050) {
            updates.add((dev, body.buffer.asByteData().getUint16(4, Endian.little)));
          }
        }
      });
    });
    final o = OpenRgbDevice('127.0.0.1:${server.port}');
    await o.open();
    expect(o.status, '2 RGB');
    o.frame(_red, 1, beat: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ids.take(2), [50, 0]); // its name, then how many controllers
    expect(ids.where((i) => i == 1100).length, 2); // custom mode on both
    expect(updates, [(0, 104), (1, 3)]);
    await o.close();
    await server.close();
  });

  test('a flash on each beat, strongest on the first of the bar', () {
    ({double phase, int beatInBar, double bpm}) b(double p, int k) =>
        (phase: p, beatInBar: k, bpm: 120);
    double level(double p, int k) => LightSync.look(
      effect: LightEffect.pulse,
      palette: const [_red],
      beat: b(p, k),
      playing: true,
      bar: 0,
      newBeat: false,
    ).level;
    expect(level(0, 0), greaterThan(level(0, 1)));
    expect(level(0, 1), greaterThan(level(0.5, 1)));
    expect(level(0.9, 0), lessThan(0.3));
    // Paused: dim and still.
    final paused = LightSync.look(
      effect: LightEffect.pulse,
      palette: const [_red],
      beat: b(0, 0),
      playing: false,
      bar: 0,
      newBeat: true,
    );
    expect(paused.level, lessThan(0.3));
    expect(paused.beat, isFalse);
    // Colour per bar walks through the cover's colours.
    final c = LightSync.look(
      effect: LightEffect.bars,
      palette: const [_red, (r: 0, g: 0, b: 255)],
      beat: b(0.2, 1),
      playing: true,
      bar: 1,
      newBeat: false,
    );
    expect(c.color, (r: 0, g: 0, b: 255));
  });
}
