import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../library/library_store.dart';
import '../player/player_handler.dart';

/// A Segue device seen on the local network right now.
class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
  });

  final String id;
  final String name;
  final String platform;
  final String host;
  final int port;

  Uri uri(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Device-to-device sync over the local network. No cloud, no account.
///
/// Every device runs a small HTTP server and announces itself with Bonjour
/// (mDNS, service `_segue._tcp`). Pairing: one device shows a 6-digit code,
/// the other enters it, and they exchange a shared token used for every
/// request after that. Sync sends each side only the rows changed since
/// the last exchange (see [LibraryStore.exportChanges]).
class SyncService {
  SyncService({
    required this.library,
    required this.player,
    this.enableDiscovery = true,
  });

  final LibraryStore library;
  final PlaybackControl player;

  /// Off in tests: devices are added by address instead.
  final bool enableDiscovery;

  static const _type = '_segue._tcp';
  static const _protocol = '1';

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  Timer? _periodic;
  Timer? _debounce;
  StreamSubscription<void>? _libSub;
  final _http = http.Client();

  String deviceName = 'Segue';
  String platform = Platform.operatingSystem;
  int get port => _server?.port ?? 0;

  /// Devices on the network right now (paired or not), by id.
  final nearby = ValueNotifier<Map<String, NearbyDevice>>({});

  /// While pairing is open: the code shown on this device.
  final pairingCode = ValueNotifier<String?>(null);
  DateTime _codeExpires = DateTime(0);

  /// Peer ids currently syncing (for the UI spinner) and last result.
  final syncing = ValueNotifier<Set<String>>({});
  final lastSync = ValueNotifier<Map<String, DateTime>>({});

  /// Shown when another device sends its playback here.
  final incomingHandoff = StreamController<String>.broadcast();

  bool _applyingRemote = false;

  Future<void> start() async {
    deviceName = await _deviceName();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
    if (enableDiscovery) await _startBonjour();

    // Sync shortly after local changes, and every minute as a safety net.
    _libSub = library.changes.listen((_) {
      if (_applyingRemote) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), syncAll);
    });
    _periodic = Timer.periodic(const Duration(seconds: 60), (_) => syncAll());
  }

  Future<void> dispose() async {
    _periodic?.cancel();
    _debounce?.cancel();
    await _libSub?.cancel();
    await _broadcast?.stop();
    await _discovery?.stop();
    await _server?.close(force: true);
    _http.close();
  }

  static Future<String> _deviceName() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isMacOS) return (await info.macOsInfo).computerName;
      if (Platform.isIOS) return (await info.iosInfo).name;
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ${a.model}';
      }
      if (Platform.isWindows) return (await info.windowsInfo).computerName;
      if (Platform.isLinux) return (await info.linuxInfo).prettyName;
    } catch (_) {}
    return Platform.localHostname;
  }

  // --- Bonjour ---------------------------------------------------------------

  Future<void> _startBonjour() async {
    try {
      _broadcast = BonsoirBroadcast(
        service: BonsoirService(
          name: 'Segue ${library.deviceId.substring(0, 8)}',
          type: _type,
          port: port,
          attributes: {
            'id': library.deviceId,
            'name': deviceName,
            'os': platform,
            'v': _protocol,
          },
        ),
      );
      await _broadcast!.initialize();
      await _broadcast!.start();

      final discovery = _discovery = BonsoirDiscovery(type: _type);
      await discovery.initialize();
      discovery.eventStream!.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            service.resolve(discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent(:final service):
          case BonsoirDiscoveryServiceUpdatedEvent(:final service):
            _onResolved(service);
          case BonsoirDiscoveryServiceLostEvent(:final service):
            final id = service.attributes['id'];
            if (id != null) nearby.value = {...nearby.value}..remove(id);
          default:
        }
      });
      await discovery.start();
    } catch (e) {
      debugPrint('Bonjour unavailable: $e');
    }
  }

  void _onResolved(BonsoirService s) {
    final id = s.attributes['id'];
    if (id == null || id == library.deviceId) return;
    final host = s.hostAddresses.firstWhere(
      (a) => !a.contains(':'), // prefer IPv4: link-local IPv6 needs a scope id
      orElse: () => s.hostAddresses.isEmpty ? '' : s.hostAddresses.first,
    );
    if (host.isEmpty) return;
    final device = NearbyDevice(
      id: id,
      name: s.attributes['name'] ?? s.name,
      platform: s.attributes['os'] ?? '',
      host: host,
      port: s.port,
    );
    nearby.value = {...nearby.value, id: device};
    final peer = library.peer(id);
    if (peer != null && (peer.host != host || peer.port != s.port)) {
      library.savePeer(
        peer.copyWith(host: host, port: s.port, name: device.name),
      );
    }
    if (peer != null) unawaited(syncWith(peer.id));
  }

  /// Adds a device by address (tests, or networks that block Bonjour).
  Future<NearbyDevice> probe(String host, int port) async {
    final res = await _http
        .get(Uri(scheme: 'http', host: host, port: port, path: '/hello'))
        .timeout(const Duration(seconds: 5));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final d = NearbyDevice(
      id: j['id'] as String,
      name: j['name'] as String,
      platform: j['os'] as String,
      host: host,
      port: port,
    );
    nearby.value = {...nearby.value, d.id: d};
    return d;
  }

  // --- Pairing ---------------------------------------------------------------

  /// Secret shared by all devices of one user ("the account"). Created on
  /// the first pairing; every device that joins gets the same one.
  String _groupToken() {
    final existing = library.getMeta('group_token');
    if (existing != null) return existing;
    final token = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    library.setMeta('group_token', token);
    return token;
  }

  /// This device's IPv4 address on the local network (for the QR code).
  Future<String?> localAddress() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    // Prefer Wi-Fi / Ethernet over VPN and virtual adapters.
    ifaces.sort((a, b) => _ifaceRank(a.name).compareTo(_ifaceRank(b.name)));
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) return a.address;
      }
    }
    return null;
  }

  static int _ifaceRank(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('en') ||
        n.startsWith('wlan') ||
        n.startsWith('wi') ||
        n.startsWith('eth')) {
      return 0;
    }
    if (n.contains('tun') || n.contains('vpn') || n.contains('bridge')) {
      return 2;
    }
    return 1;
  }

  /// What the pairing QR code encodes.
  Future<String?> pairingLink() async {
    final code = pairingCode.value;
    final host = await localAddress();
    if (code == null || host == null) return null;
    return Uri(
      scheme: 'segue',
      host: 'pair',
      queryParameters: {'h': host, 'p': '$port', 'c': code, 'n': deviceName},
    ).toString();
  }

  /// Joins using a scanned QR link (segue://pair?h=…&p=…&c=…).
  Future<Peer> joinWithLink(String link) async {
    final uri = Uri.tryParse(link.trim());
    final q = uri?.queryParameters ?? const {};
    if (uri?.scheme != 'segue' ||
        q['h'] == null ||
        q['p'] == null ||
        q['c'] == null) {
      throw SyncException('Это не QR-код Segue');
    }
    final device = await probe(q['h']!, int.parse(q['p']!));
    return pair(device, q['c']!);
  }

  /// Joins with just the 6-digit code: tries every Segue device nearby;
  /// only the one showing that code accepts.
  Future<Peer> joinWithCode(String code) async {
    final candidates = nearby.value.values
        .where((d) => library.peer(d.id) == null)
        .toList();
    if (candidates.isEmpty) {
      throw SyncException(
        'Рядом нет устройств с Segue. Они должны быть в одной Wi-Fi-сети',
      );
    }
    for (final d in candidates) {
      try {
        return await pair(d, code);
      } catch (_) {
        continue; // not the device showing this code
      }
    }
    throw SyncException('Код не подошёл ни одному устройству рядом');
  }

  /// Shows a code on this device for 3 minutes.
  String openPairing() {
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    pairingCode.value = code;
    _codeExpires = DateTime.now().add(const Duration(minutes: 3));
    return code;
  }

  void closePairing() => pairingCode.value = null;

  /// Pairs with [device] using the code it shows.
  Future<Peer> pair(NearbyDevice device, String code) async {
    final res = await _http
        .post(
          device.uri('/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': code.trim(),
            'id': library.deviceId,
            'name': deviceName,
            'os': platform,
            'port': port,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 403) {
      throw SyncException('Неверный или устаревший код');
    }
    if (res.statusCode != 200) {
      throw SyncException('Устройство не ответило (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    // Join their group: from now on we share one secret with all of them.
    library.setMeta('group_token', j['token'] as String);
    final peer = Peer(
      id: j['id'] as String,
      name: j['name'] as String,
      platform: j['os'] as String,
      token: j['token'] as String,
      host: device.host,
      port: device.port,
    );
    library.savePeer(peer);
    await syncWith(peer.id); // pull the whole library right away
    return peer;
  }

  void unpair(String id) => library.removePeer(id);

  // --- Sync ------------------------------------------------------------------

  Future<void> syncAll() async {
    for (final p in library.peers()) {
      if (p.host != null) unawaited(syncWith(p.id));
    }
  }

  /// One round both ways: we send our changes and get theirs back.
  Future<int> syncWith(String peerId) async {
    final peer = library.peer(peerId);
    if (peer == null || peer.host == null || syncing.value.contains(peerId)) {
      return 0;
    }
    syncing.value = {...syncing.value, peerId};
    try {
      final mine = library.exportChanges(peer.sentSeq);
      final res = await _http
          .post(
            _peerUri(peer, '/sync'),
            headers: _auth(peer),
            body: jsonEncode({
              'changes': mine,
              'since': peer.recvSeq,
              'members': _members(except: peer.id),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw SyncException('sync ${res.statusCode}');
      final reply = jsonDecode(res.body) as Map<String, dynamic>;
      final theirs = reply['changes'] as Map<String, dynamic>;
      _learnMembers(reply['members'] as List?, peer.token);
      final applied = _applyRemote(theirs);
      library.savePeer(
        library
            .peer(peerId)!
            .copyWith(
              sentSeq: mine['seq']! as int,
              recvSeq: theirs['seq'] as int,
            ),
      );
      lastSync.value = {...lastSync.value, peerId: DateTime.now()};
      return applied;
    } catch (e) {
      debugPrint('sync with ${peer.name} failed: $e');
      return 0;
    } finally {
      syncing.value = {...syncing.value}..remove(peerId);
    }
  }

  int _applyRemote(Map<String, dynamic> changes) {
    _applyingRemote = true;
    try {
      return library.applyChanges(changes);
    } finally {
      // Let the change notification pass before re-enabling auto-sync.
      Future<void>.delayed(Duration.zero, () => _applyingRemote = false);
    }
  }

  /// Other devices of the group we know, so membership spreads: a phone
  /// that joined via the laptop also learns about the tablet.
  List<Map<String, Object?>> _members({required String except}) => [
    for (final p in library.peers())
      if (p.id != except)
        {
          'id': p.id,
          'name': p.name,
          'os': p.platform,
          'host': p.host,
          'port': p.port,
        },
  ];

  void _learnMembers(List? members, String token) {
    for (final m in (members ?? const []).cast<Map>()) {
      final id = m['id'] as String?;
      if (id == null || id == library.deviceId || library.peer(id) != null) {
        continue;
      }
      library.savePeer(
        Peer(
          id: id,
          name: (m['name'] as String?) ?? 'Устройство',
          platform: (m['os'] as String?) ?? '',
          token: token,
          host: m['host'] as String?,
          port: m['port'] as int?,
        ),
      );
    }
  }

  // --- Handoff ---------------------------------------------------------------

  /// Moves what's playing here to [peerId] and pauses this device.
  Future<void> sendPlayback(String peerId) async {
    final peer = library.peer(peerId);
    if (peer == null) throw SyncException('Устройство не найдено');
    final snap = player.snapshot();
    if ((snap['queue'] as List).isEmpty) {
      throw SyncException('Сейчас ничего не играет');
    }
    final res = await _http
        .post(
          _peerUri(peer, '/play'),
          headers: _auth(peer),
          body: jsonEncode({...snap, 'from': deviceName}),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw SyncException('${peer.name} не ответил');
    await player.pause();
  }

  /// Takes over what's playing on [peerId] and pauses it there.
  Future<void> takePlayback(String peerId) async {
    final peer = library.peer(peerId);
    if (peer == null) throw SyncException('Устройство не найдено');
    final res = await _http
        .post(_peerUri(peer, '/take'), headers: _auth(peer))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 204) {
      throw SyncException('На ${peer.name} ничего не играет');
    }
    if (res.statusCode != 200) throw SyncException('${peer.name} не ответил');
    await player.restore(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Whether a paired device is reachable on the network now.
  bool isOnline(String peerId) => nearby.value.containsKey(peerId);

  Uri _peerUri(Peer p, String path) {
    final live = nearby.value[p.id];
    return Uri(
      scheme: 'http',
      host: live?.host ?? p.host,
      port: live?.port ?? p.port,
      path: path,
    );
  }

  Map<String, String> _auth(Peer p) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${p.token}',
    'X-Segue-Device': library.deviceId,
    // Lets a group member that hasn't met us yet add us right away.
    'X-Segue-Name': Uri.encodeComponent(deviceName),
    'X-Segue-Os': platform,
    'X-Segue-Port': '$port',
  };

  // --- Server ----------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (path == '/hello' && req.method == 'GET') {
        return await _json(res, {
          'id': library.deviceId,
          'name': deviceName,
          'os': platform,
          'v': _protocol,
        });
      }
      final body = req.method == 'POST'
          ? await utf8.decoder.bind(req).join()
          : '';
      if (path == '/pair' && req.method == 'POST') {
        return await _onPair(req, res, body);
      }

      // Everything else needs a paired device's token.
      final deviceId = req.headers.value('X-Segue-Device') ?? '';
      final token = req.headers
          .value('Authorization')
          ?.replaceFirst('Bearer ', '');
      var peer = library.peer(deviceId);
      // A group member we haven't met yet (it joined via another device):
      // the shared group secret is enough; remember it from now on.
      final group = library.getMeta('group_token');
      if (peer == null &&
          deviceId.isNotEmpty &&
          group != null &&
          token == group) {
        peer = Peer(
          id: deviceId,
          name: Uri.decodeComponent(
            req.headers.value('X-Segue-Name') ?? 'Устройство',
          ),
          platform: req.headers.value('X-Segue-Os') ?? '',
          token: group,
          host: req.connectionInfo?.remoteAddress.address,
          port: int.tryParse(req.headers.value('X-Segue-Port') ?? ''),
        );
        library.savePeer(peer);
      }
      if (peer == null || token != peer.token) {
        res.statusCode = 401;
        return await res.close();
      }
      // Remember where the peer called from.
      final from = req.connectionInfo?.remoteAddress.address;
      if (from != null && from != peer.host) {
        library.savePeer(peer.copyWith(host: from));
      }

      switch (path) {
        case '/sync':
          final j = jsonDecode(body) as Map<String, dynamic>;
          final changes = j['changes'] as Map<String, dynamic>;
          _applyRemote(changes);
          final reply = library.exportChanges(j['since'] as int? ?? 0);
          _learnMembers(j['members'] as List?, peer.token);
          library.savePeer(
            library
                .peer(peer.id)!
                .copyWith(
                  recvSeq: changes['seq'] as int,
                  sentSeq: reply['seq']! as int,
                ),
          );
          lastSync.value = {...lastSync.value, peer.id: DateTime.now()};
          return await _json(res, {
            'changes': reply,
            'members': _members(except: peer.id),
          });
        case '/play':
          final snap = jsonDecode(body) as Map<String, dynamic>;
          await player.restore(snap);
          incomingHandoff.add(snap['from'] as String? ?? peer.name);
          return await _json(res, {'ok': true});
        case '/take':
          final snap = player.snapshot();
          if ((snap['queue'] as List).isEmpty) {
            res.statusCode = 204;
            return await res.close();
          }
          await player.pause();
          return await _json(res, snap);
      }
      res.statusCode = 404;
      await res.close();
    } catch (e) {
      res.statusCode = 500;
      await res.close();
    }
  }

  Future<void> _onPair(HttpRequest req, HttpResponse res, String body) async {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final code = pairingCode.value;
    if (code == null ||
        DateTime.now().isAfter(_codeExpires) ||
        j['code'] != code) {
      res.statusCode = 403;
      return res.close();
    }
    final token = _groupToken();
    library.savePeer(
      Peer(
        id: j['id'] as String,
        name: j['name'] as String,
        platform: j['os'] as String,
        token: token,
        host: req.connectionInfo?.remoteAddress.address,
        port: j['port'] as int?,
      ),
    );
    closePairing();
    return await _json(res, {
      'id': library.deviceId,
      'name': deviceName,
      'os': platform,
      'token': token,
    });
  }

  Future<void> _json(HttpResponse res, Object body) async {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }
}
