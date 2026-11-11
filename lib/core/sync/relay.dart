import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_buffers.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';

/// Another device of this user, as seen through the relay.
@immutable
class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.online = false,
    this.state,
    this.stateAt,
  });

  final String id;
  final String name;
  final String platform;
  final bool online;

  /// Its player (see [PlaybackControl.snapshot]) and when that was taken,
  /// by its clock.
  final Map<String, dynamic>? state;
  final DateTime? stateAt;

  bool get playing => online && state?['playing'] == true;

  /// The track it plays (from its queue), if any.
  Map<String, dynamic>? get track {
    final q = state?['queue'] as List?;
    final i = state?['index'] as int? ?? -1;
    return q == null || i < 0 || i >= q.length
        ? null
        : (q[i] as Map).cast<String, dynamic>();
  }

  /// Where playback is now, moving on from the reported position.
  Duration get position {
    final ms = state?['positionMs'] as int? ?? 0;
    final at = stateAt;
    if (!playing || at == null) return Duration(milliseconds: ms);
    final p = Duration(milliseconds: ms) + DateTime.now().difference(at);
    final total = state?['durationMs'] as int?;
    return total != null && p.inMilliseconds > total
        ? Duration(milliseconds: total)
        : p;
  }

  Duration? get duration {
    final ms = state?['durationMs'] as int?;
    return ms == null ? null : Duration(milliseconds: ms);
  }

  double get volume => (state?['volume'] as num?)?.toDouble() ?? 1;

  RemoteDevice copyWith({
    String? name,
    String? platform,
    bool? online,
    Map<String, dynamic>? state,
    DateTime? stateAt,
  }) => RemoteDevice(
    id: id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    online: online ?? this.online,
    state: state ?? this.state,
    stateAt: stateAt ?? this.stateAt,
  );
}

/// Sync and remote control across any networks, through public MQTT
/// brokers. No server of our own and no account.
///
/// Everything is end-to-end encrypted with a key derived from the group
/// secret only this user's devices have (AES-256-GCM); the brokers see
/// random topic names and ciphertext. Devices connect to two brokers at
/// once and dedupe, so one broker going down changes nothing.
///
/// Per device, under the group's topic:
/// - `p/<id>` presence (retained; a last-will marks it offline)
/// - `l/<id>/m`, `l/<id>/<n>` the whole library, gzipped, in chunks
///   (retained, so a device that was off catches up on connect)
/// - `s/<id>` what its player is doing (retained)
/// - `c/<id>` commands to it: play, pause, seek, next, take over…
class Relay {
  Relay({
    required this.library,
    required this.player,
    required this.deviceName,
    String? platform,
    this.brokers = defaultBrokers,
  }) : platform = platform ?? Platform.operatingSystem;

  final LibraryStore library;
  final PlaybackControl player;
  final String Function() deviceName;
  final String platform;
  final List<String> brokers;

  static const defaultBrokers = ['broker.hivemq.com', 'broker.emqx.io'];

  /// Chunk size for the library: below every broker's message limit.
  static const _chunk = 48 * 1024;

  /// Other devices of the group, by id.
  final devices = ValueNotifier<Map<String, RemoteDevice>>({});

  /// Connected to at least one broker.
  final connected = ValueNotifier<bool>(false);

  /// Name of a device that just handed its music over to this one.
  final incoming = StreamController<String>.broadcast();

  /// While this device invites another one: the code it shows.
  final inviteCode = ValueNotifier<String?>(null);

  final _clients = <MqttServerClient>[];
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<void>? _libSub, _playerSub;
  Timer? _libDebounce, _stateDebounce, _inviteTimer;
  SecretKey? _key;
  String _base = '';
  int _publishedSeq = -1;
  final _seenCommands = <String>{};
  final _chunks = <String, Map<int, Uint8List>>{}; // "<device>/<rev>" → parts
  final _manifests = <String, Map<String, dynamic>>{};
  var _running = false;

  String get _me => library.deviceId;

  // --- keys --------------------------------------------------------------------

  /// The group secret, shared by all of this user's devices.
  String groupToken() {
    final existing = library.getMeta('group_token');
    if (existing != null && existing.isNotEmpty) return existing;
    final token = base64Url.encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    library.setMeta('group_token', token);
    return token;
  }

  static Future<String> hash(String s) async {
    final h = await Sha256().hash(utf8.encode(s));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<SecretKey> _groupKey(String token) =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(utf8.encode(token)),
        info: utf8.encode('segue-relay-v1'),
        nonce: const [],
      );

  static final _aes = AesGcm.with256bits();

  /// version byte, 12-byte nonce, ciphertext, 16-byte tag.
  static Future<Uint8List> seal(SecretKey key, List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: key);
    return Uint8List.fromList([
      1,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<List<int>?> open(SecretKey key, List<int> data) async {
    if (data.length < 29 || data[0] != 1) return null;
    try {
      return await _aes.decrypt(
        SecretBox(
          data.sublist(13, data.length - 16),
          nonce: data.sublist(1, 13),
          mac: Mac(data.sublist(data.length - 16)),
        ),
        secretKey: key,
      );
    } catch (_) {
      return null; // not ours, or tampered with
    }
  }

  Future<Uint8List> _sealJson(Object json) async =>
      seal(_key!, gzip.encode(utf8.encode(jsonEncode(json))));

  Future<Map<String, dynamic>?> _openJson(List<int> data) async {
    final plain = await open(_key!, data);
    if (plain == null) return null;
    try {
      return jsonDecode(utf8.decode(gzip.decode(plain)))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // --- connection --------------------------------------------------------------

  Future<void> start() async {
    if (_running) return;
    _running = true;
    final token = groupToken();
    _key = await _groupKey(token);
    _base = 'segue/v1/${(await hash('segue-topic:$token')).substring(0, 24)}';
    await Future.wait([for (final host in brokers) _connect(host)]);

    _libSub = library.changes.listen((_) => _scheduleLibrary());
    _playerSub = player.stateChanges.listen((_) => _scheduleState());
    _scheduleLibrary(immediately: true);
    _scheduleState();
  }

  Future<void> stop() async {
    _running = false;
    _libDebounce?.cancel();
    _stateDebounce?.cancel();
    await _libSub?.cancel();
    await _playerSub?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final c in _clients) {
      try {
        // Leave politely: the will isn't sent on a clean disconnect.
        await _publishTo(
          c,
          '$_base/p/$_me',
          await _sealJson({
            'name': deviceName(),
            'os': platform,
            'online': false,
          }),
          retain: true,
        );
        c.disconnect();
      } catch (_) {}
    }
    _clients.clear();
    connected.value = false;
    devices.value = {};
    _publishedSeq = -1;
  }

  /// After the group changed (joined another device's group).
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> _connect(String host) async {
    final id = 'sg-${_me.substring(0, 8)}-${Random().nextInt(1 << 30)}';
    final c = MqttServerClient.withPort(host, id, 8883)
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .startClean()
        .withWillTopic('$_base/p/$_me')
        // The will can only carry text: a plain "off" (no data in it).
        .withWillMessage('off')
        .withWillRetain()
        .withWillQos(MqttQos.atLeastOnce);
    c.onConnected = () => _onConnected(c);
    c.onAutoReconnected = () => _onConnected(c);
    c.onDisconnected = () => connected.value = _clients.any(
      (x) => x.connectionStatus?.state == MqttConnectionState.connected,
    );
    try {
      await c.connect().timeout(const Duration(seconds: 12));
      _clients.add(c);
      _subs.add(c.updates!.listen(_onMessages));
      c.subscribe('$_base/#', MqttQos.atLeastOnce);
      _onConnected(c);
    } catch (e) {
      debugPrint('relay $host: $e');
      c.disconnect();
    }
  }

  Future<void> _onConnected(MqttServerClient c) async {
    connected.value = true;
    await _publishTo(
      c,
      '$_base/p/$_me',
      await _sealJson({'name': deviceName(), 'os': platform, 'online': true}),
      retain: true,
    );
    // A broker that was down missed what we published meanwhile.
    _publishedSeq = -1;
    _scheduleLibrary(immediately: true);
    _scheduleState();
  }

  Future<void> _publishTo(
    MqttServerClient c,
    String topic,
    List<int> data, {
    bool retain = false,
  }) async {
    if (c.connectionStatus?.state != MqttConnectionState.connected) return;
    c.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      Uint8Buffer()..addAll(data),
      retain: retain,
    );
  }

  Future<void> _publish(String topic, List<int> data, {bool retain = false}) =>
      Future.wait([
        for (final c in _clients) _publishTo(c, topic, data, retain: retain),
      ]);

  // --- incoming ----------------------------------------------------------------

  Future<void> _onMessages(List<MqttReceivedMessage<MqttMessage>> batch) async {
    for (final m in batch) {
      final topic = m.topic;
      final data = (m.payload as MqttPublishMessage).payload.message.toList();
      if (topic.startsWith('segue/v1/i/')) {
        await _onInvite(topic, data);
        continue;
      }
      if (!topic.startsWith('$_base/') || data.isEmpty) continue;
      final parts = topic.substring(_base.length + 1).split('/');
      if (parts.length < 2) continue;
      final kind = parts[0], from = parts[1];
      if (kind == 'c') {
        if (from == _me) await _onCommand(data);
        continue;
      }
      if (from == _me) continue;
      switch (kind) {
        case 'p':
          final j = utf8.decode(data, allowMalformed: true) == 'off'
              ? <String, dynamic>{'online': false}
              : await _openJson(data);
          if (j != null) _onPresence(from, j);
        case 's':
          final j = await _openJson(data);
          if (j != null) _onState(from, j);
        case 'l':
          if (parts.length == 3) await _onLibraryPart(from, parts[2], data);
      }
    }
  }

  Set<String> get _ignored {
    try {
      return {
        for (final x
            in jsonDecode(library.getMeta('ignored_devices') ?? '[]') as List)
          x as String,
      };
    } catch (_) {
      return {};
    }
  }

  /// Stops showing device [id] here (see Connect.forget).
  void ignore(String id) {
    library.setMeta('ignored_devices', jsonEncode([..._ignored, id]));
    devices.value = {...devices.value}..remove(id);
  }

  void _onPresence(String id, Map<String, dynamic> j) {
    if (_ignored.contains(id)) return;
    final old = devices.value[id];
    final name = j['name'] as String? ?? old?.name ?? 'Устройство';
    final os = j['os'] as String? ?? old?.platform ?? '';
    devices.value = {
      ...devices.value,
      id: (old ?? RemoteDevice(id: id, name: name, platform: os)).copyWith(
        name: name,
        platform: os,
        online: j['online'] == true,
      ),
    };
    // Shows up in the devices list next to the ones paired on Wi-Fi.
    final peer = library.peer(id);
    if (peer == null) {
      library.savePeer(
        Peer(id: id, name: name, platform: os, token: groupToken()),
      );
    } else if (peer.name != name) {
      library.savePeer(peer.copyWith(name: name));
    }
    // Someone used our invite: it's done.
    if (inviteCode.value != null && j['online'] == true && old == null) {
      closeInvite();
    }
  }

  void _onState(String id, Map<String, dynamic> j) {
    if (_ignored.contains(id)) return;
    final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0);
    final old =
        devices.value[id] ??
        RemoteDevice(id: id, name: 'Устройство', platform: '');
    devices.value = {
      ...devices.value,
      id: old.copyWith(
        state: (j['player'] as Map).cast<String, dynamic>(),
        // Their clock may differ from ours: count from when it arrived,
        // unless it's an old retained message.
        stateAt:
            DateTime.now().difference(at).abs() < const Duration(seconds: 5)
            ? DateTime.now()
            : at,
      ),
    };
  }

  Future<void> _onLibraryPart(String from, String part, List<int> data) async {
    final plain = await open(_key!, data);
    if (plain == null) return;
    if (part == 'm') {
      final m = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      _manifests[from] = m;
    } else {
      final i = int.tryParse(part);
      if (i == null || plain.length < 16) return;
      final rev = utf8.decode(plain.sublist(0, 16));
      (_chunks['$from/$rev'] ??= {})[i] = Uint8List.fromList(plain.sublist(16));
    }
    final m = _manifests[from];
    if (m == null) return;
    final rev = m['rev'] as String, n = m['n'] as int;
    final got = _chunks['$from/$rev'];
    if (got == null || got.length < n) return;
    final blob = BytesBuilder();
    for (var k = 0; k < n; k++) {
      final c = got[k];
      if (c == null) return;
      blob.add(c);
    }
    _chunks.removeWhere((k, _) => k.startsWith('$from/'));
    _manifests.remove(from);
    try {
      final changes = jsonDecode(
        utf8.decode(gzip.decode(blob.toBytes())),
      ) as Map<String, dynamic>;
      final applied = library.applyChanges(changes);
      debugPrint('relay: library from $from, $applied rows applied');
    } catch (e) {
      debugPrint('relay library: $e');
    }
  }

  // --- outgoing: library and player -------------------------------------------

  void _scheduleLibrary({bool immediately = false}) {
    _libDebounce?.cancel();
    _libDebounce = Timer(
      immediately ? Duration.zero : const Duration(seconds: 2),
      _publishLibrary,
    );
  }

  /// The whole library (history trimmed to the latest plays), so a device
  /// that was offline gets everything from the retained copy.
  Future<void> _publishLibrary() async {
    if (_clients.isEmpty || library.currentSeq == _publishedSeq) return;
    final seq = library.currentSeq;
    final all = Map<String, Object>.of(library.exportChanges(0));
    final history = all['history'] as List;
    if (history.length > 400) {
      all['history'] = history.sublist(history.length - 400);
    }
    final blob = gzip.encode(utf8.encode(jsonEncode(all)));
    final rev = randomId(16);
    final n = (blob.length / _chunk).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < n; i++) {
      final part = blob.sublist(i * _chunk, min((i + 1) * _chunk, blob.length));
      await _publish(
        '$_base/l/$_me/$i',
        await seal(_key!, [...utf8.encode(rev), ...part]),
        retain: true,
      );
    }
    // The manifest last: receivers wait for it before assembling.
    await _publish(
      '$_base/l/$_me/m',
      await seal(_key!, utf8.encode(jsonEncode({'rev': rev, 'n': n}))),
      retain: true,
    );
    // Old chunks beyond the new count would linger: clear a few.
    final prev = int.tryParse(library.getMeta('relay_chunks') ?? '') ?? 0;
    for (var i = n; i < prev; i++) {
      await _publish('$_base/l/$_me/$i', const [], retain: true);
    }
    library.setMeta('relay_chunks', '$n');
    _publishedSeq = seq;
  }

  void _scheduleState() {
    _stateDebounce?.cancel();
    _stateDebounce = Timer(const Duration(milliseconds: 250), _publishState);
  }

  Future<void> _publishState() async {
    if (_clients.isEmpty) return;
    final snap = Map<String, dynamic>.of(player.snapshot());
    // Others only show the current track and what's next: keep it small.
    final queue = (snap['queue'] as List?) ?? const [];
    final index = snap['index'] as int? ?? -1;
    if (queue.length > 60) {
      final from = max(0, index - 10);
      snap['queue'] = queue.sublist(from, min(queue.length, from + 60));
      snap['index'] = index - from;
      // Remotes pick queue items by their index in the full queue.
      snap['offset'] = from;
    }
    await _publish(
      '$_base/s/$_me',
      await _sealJson({
        'at': DateTime.now().millisecondsSinceEpoch,
        'player': snap,
      }),
      retain: true,
    );
  }

  // --- commands (remote control) -------------------------------------------

  /// Sends [op] to device [id]: play, pause, next, prev, seek (ms),
  /// volume (v), item (i), restore (snapshot), handoff.
  Future<void> command(
    String id,
    String op, [
    Map<String, dynamic>? args,
  ]) async {
    await _publish(
      '$_base/c/$id',
      await _sealJson({
        'op': op,
        'id': randomId(12),
        'from': _me,
        'fromName': deviceName(),
        ...?args,
      }),
    );
  }

  Future<void> _onCommand(List<int> data) async {
    final j = await _openJson(data);
    if (j == null) return;
    // Each command arrives once per broker.
    if (!_seenCommands.add(j['id'] as String? ?? '')) return;
    if (_seenCommands.length > 200) _seenCommands.remove(_seenCommands.first);
    switch (j['op']) {
      case 'play':
        await player.play();
      case 'pause':
        await player.pause();
      case 'next':
        await player.skipToNext();
      case 'prev':
        await player.skipToPrevious();
      case 'seek':
        await player.seek(Duration(milliseconds: j['ms'] as int? ?? 0));
      case 'volume':
        await player.setVolume((j['v'] as num?)?.toDouble() ?? 1);
      case 'item':
        await player.skipToQueueItem(j['i'] as int? ?? 0);
      case 'add':
        await player.addNext(
          Track.fromJson((j['track'] as Map).cast<String, dynamic>()),
        );
      case 'giveTo':
        await handOffTo(j['to'] as String);
      case 'restore':
        // Another device moves its music here.
        await player.restore((j['snapshot'] as Map).cast<String, dynamic>());
        incoming.add(j['fromName'] as String? ?? 'другого устройства');
    }
    _scheduleState();
  }

  /// Moves what plays here to [id], continuing at the same moment.
  Future<void> handOffTo(String id) async {
    final snap = player.snapshot();
    if ((snap['queue'] as List).isEmpty) return;
    await command(id, 'restore', {'snapshot': snap});
    await player.pause();
  }

  /// Brings what plays on [id] here: that device sends its exact state
  /// and pauses. If it doesn't answer, continues from what we last saw.
  Future<void> takeFrom(String id) async {
    final d = devices.value[id];
    final arrived = incoming.stream.first.timeout(const Duration(seconds: 4));
    await command(id, 'giveTo', {'to': _me});
    try {
      await arrived;
    } on TimeoutException {
      final state = d?.state;
      if (d == null ||
          state == null ||
          (state['queue'] as List?)?.isEmpty != false) {
        return;
      }
      await player.restore({...state, 'positionMs': d.position.inMilliseconds});
    }
  }

  // --- invites (pairing across networks) ---------------------------------------

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String randomId(int n) {
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(
        n,
        (_) => _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
      ),
    );
  }

  /// "ABCD-EFGH" → "ABCDEFGH"; null when it can't be an invite code.
  static String? normalizeCode(String code) {
    final c = code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (c.length != 8) return null;
    for (final ch in c.split('')) {
      if (!_alphabet.contains(ch)) return null;
    }
    return c;
  }

  static Future<(String topic, SecretKey key)> _inviteKeys(String code) =>
      codeKeys(code, 'invite', 'segue/v1/i');

  /// Topic and key for something shared by a short code (invites, listening
  /// together).
  static Future<(String topic, SecretKey key)> codeKeys(
    String code,
    String purpose,
    String prefix,
  ) async {
    final topic =
        '$prefix/${(await hash('segue-$purpose:$code')).substring(0, 24)}';
    // Slow on purpose: guessing codes offline must not pay off.
    final key =
        await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 60000,
          bits: 256,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(code)),
          nonce: utf8.encode('segue-$purpose-v1'),
        );
    return (topic, key);
  }

  /// Opens an invite for 10 minutes. Another device that enters the code
  /// (or scans it) joins this group, on any network.
  Future<String> openInvite() async {
    final code = randomId(8);
    inviteCode.value = code;
    final (topic, key) = await _inviteKeys(code);
    final sealed = await seal(
      key,
      utf8.encode(
        jsonEncode({'token': groupToken(), 'name': deviceName(), 'id': _me}),
      ),
    );
    await _publish(topic, sealed, retain: true);
    _inviteTopic = topic;
    _inviteTimer?.cancel();
    _inviteTimer = Timer(const Duration(minutes: 10), closeInvite);
    return code;
  }

  String? _inviteTopic;

  void closeInvite() {
    _inviteTimer?.cancel();
    inviteCode.value = null;
    final t = _inviteTopic;
    _inviteTopic = null;
    if (t != null) unawaited(_publish(t, const [], retain: true));
  }

  Completer<Map<String, dynamic>>? _joining;
  SecretKey? _joinKey;

  Future<void> _onInvite(String topic, List<int> data) async {
    final key = _joinKey, done = _joining;
    if (key == null || done == null || done.isCompleted || data.isEmpty) return;
    final plain = await open(key, data);
    if (plain == null) return;
    done.complete(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
  }

  /// Joins the group of the device showing [code]. Returns its name.
  Future<String> join(String code) async {
    final c = normalizeCode(code);
    if (c == null) throw const FormatException('Код из 8 букв и цифр');
    if (_clients.isEmpty) throw StateError('Нет связи с интернетом');
    final (topic, key) = await _inviteKeys(c);
    _joinKey = key;
    final done = _joining = Completer<Map<String, dynamic>>();
    for (final cl in _clients) {
      cl.subscribe(topic, MqttQos.atLeastOnce);
    }
    try {
      final invite = await done.future.timeout(const Duration(seconds: 15));
      for (final cl in _clients) {
        cl.unsubscribe(topic);
      }
      final token = invite['token'] as String;
      if (token != library.getMeta('group_token')) {
        library.setMeta('group_token', token);
        await restart();
      }
      return invite['name'] as String? ?? 'устройство';
    } on TimeoutException {
      throw StateError('Код не найден или устарел');
    } finally {
      _joining = null;
      _joinKey = null;
    }
  }
}
