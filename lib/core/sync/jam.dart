import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_buffers.dart';

import '../models/track.dart';
import '../player/player_handler.dart';
import 'relay.dart';

/// Someone in the session.
@immutable
class JamMember {
  const JamMember(this.id, this.name, {this.host = false});
  final String id;
  final String name;
  final bool host;
}

/// "Слушать вместе": friends hear the same music at the same moment, each
/// on their own device, and can add songs to the shared queue.
///
/// The host's player leads. It publishes what plays (track, position,
/// paused or not) to a room on the public relay brokers, encrypted with a
/// key derived from the 8-character room code; guests follow it, correcting
/// drift every couple of seconds. Guests send "add this song" requests.
class JamService {
  JamService({
    required this.player,
    required this.deviceId,
    required this.name,
    this.brokers = Relay.defaultBrokers,
  });

  final PlaybackControl player;
  final String deviceId;
  final String Function() name;
  final List<String> brokers;

  /// The room code while in a session.
  final code = ValueNotifier<String?>(null);
  final isHost = ValueNotifier<bool>(false);
  final members = ValueNotifier<List<JamMember>>(const []);

  /// Host name and the next songs, as guests see them.
  final hostName = ValueNotifier<String>('');
  final upcoming = ValueNotifier<List<Track>>(const []);

  /// "X added a song", "X joined"…
  final events = StreamController<String>.broadcast();

  bool get active => code.value != null;

  final _clients = <MqttServerClient>[];
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<void>? _playerSub;
  Timer? _beat, _drift, _stateDebounce;
  SecretKey? _key;
  String _base = '';
  final _seen = <String>{};
  final _memberMap = <String, JamMember>{};

  // Last host state a guest got, and when (our clock).
  Map<String, dynamic>? _hostState;
  DateTime _hostAt = DateTime(0);

  /// Starts a session with what plays here. Returns the code to share.
  Future<String> host() async {
    await leave();
    final c = Relay.randomId(8);
    await _open(c, asHost: true);
    _playerSub = player.stateChanges.listen((_) => _scheduleState());
    // Guests that join later, and clock drift: a regular heartbeat.
    _beat = Timer.periodic(const Duration(seconds: 4), (_) => _publishState());
    await _publishState();
    return c;
  }

  /// Joins a friend's session by code or segue://jam link. Returns the
  /// host's name once the first state arrived.
  Future<String> join(String input) async {
    final uri = Uri.tryParse(input.trim());
    final raw = uri != null && uri.scheme == 'segue'
        ? uri.queryParameters['c'] ?? ''
        : input;
    final c = Relay.normalizeCode(raw);
    if (c == null) throw const FormatException('Код из 8 букв и цифр');
    await leave();
    await _open(c, asHost: false);
    final first = Completer<void>();
    late final VoidCallback l;
    l = () {
      if (hostName.value.isNotEmpty && !first.isCompleted) first.complete();
    };
    hostName.addListener(l);
    l(); // it may have arrived already, while connecting
    try {
      await first.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      await leave();
      throw StateError('Совместное прослушивание не найдено или закончилось');
    } finally {
      hostName.removeListener(l);
    }
    _drift = Timer.periodic(const Duration(seconds: 2), (_) => _follow());
    return hostName.value;
  }

  /// Guests: asks the host to add [t] to the shared queue.
  Future<void> suggest(Track t) => _send('a', {
    'track': t.toJson(),
    'from': name(),
    'id': Relay.randomId(10),
  });

  Future<void> leave() async {
    if (!active) return;
    _beat?.cancel();
    _drift?.cancel();
    _stateDebounce?.cancel();
    await _playerSub?.cancel();
    _playerSub = null;
    if (isHost.value) await _send('h', {'open': false}, retain: true);
    await _send('m/$deviceId', {'online': false}, retain: true);
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final c in _clients) {
      c.disconnect();
    }
    _clients.clear();
    _memberMap.clear();
    members.value = const [];
    upcoming.value = const [];
    hostName.value = '';
    _hostState = null;
    isHost.value = false;
    code.value = null;
  }

  // --- connection ---------------------------------------------------------------

  Future<void> _open(String c, {required bool asHost}) async {
    final (topic, key) = await Relay.codeKeys(c, 'jam', 'segue/v1/j');
    _key = key;
    _base = topic;
    isHost.value = asHost;
    code.value = c;
    await Future.wait([for (final h in brokers) _connect(h)]);
    if (_clients.isEmpty) {
      code.value = null;
      throw StateError('Нет связи с интернетом');
    }
    await _send('m/$deviceId', {
      'online': true,
      'name': name(),
      'host': asHost,
    }, retain: true);
  }

  Future<void> _connect(String host) async {
    final id = 'sgj-${deviceId.substring(0, 8)}-${Random().nextInt(1 << 30)}';
    final c = MqttServerClient.withPort(host, id, 8883)
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .startClean()
        .withWillTopic('$_base/m/$deviceId')
        .withWillMessage('off')
        .withWillRetain()
        .withWillQos(MqttQos.atLeastOnce);
    try {
      await c.connect().timeout(const Duration(seconds: 12));
      _clients.add(c);
      _subs.add(c.updates!.listen(_onMessages));
      c.subscribe('$_base/#', MqttQos.atLeastOnce);
    } catch (e) {
      debugPrint('jam $host: $e');
      c.disconnect();
    }
  }

  Future<void> _send(
    String sub,
    Map<String, dynamic> body, {
    bool retain = false,
  }) async {
    final key = _key;
    if (key == null) return;
    final data = await Relay.seal(
      key,
      gzip.encode(utf8.encode(jsonEncode(body))),
    );
    for (final c in _clients) {
      if (c.connectionStatus?.state != MqttConnectionState.connected) continue;
      c.publishMessage(
        '$_base/$sub',
        MqttQos.atLeastOnce,
        Uint8Buffer()..addAll(data),
        retain: retain,
      );
    }
  }

  Future<void> _onMessages(List<MqttReceivedMessage<MqttMessage>> batch) async {
    for (final m in batch) {
      final data = (m.payload as MqttPublishMessage).payload.message.toList();
      if (!m.topic.startsWith('$_base/') || data.isEmpty) continue;
      final parts = m.topic.substring(_base.length + 1).split('/');
      if (parts.first == 'm' && parts.length == 2) {
        final id = parts[1];
        if (utf8.decode(data, allowMalformed: true) == 'off') {
          _memberLeft(id);
          continue;
        }
      }
      final plain = await Relay.open(_key!, data);
      if (plain == null) continue;
      Map<String, dynamic> j;
      try {
        j = jsonDecode(utf8.decode(gzip.decode(plain))) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (parts.first) {
        case 'm' when parts.length == 2:
          if (j['online'] == true) {
            _memberJoined(
              parts[1],
              j['name'] as String? ?? 'Гость',
              host: j['host'] == true,
            );
          } else {
            _memberLeft(parts[1]);
          }
        case 'h':
          if (!isHost.value) _onHostState(j);
        case 'a':
          if (isHost.value) await _onSuggest(j);
      }
    }
  }

  void _memberJoined(String id, String who, {bool host = false}) {
    final isNew = !_memberMap.containsKey(id);
    _memberMap[id] = JamMember(id, who, host: host);
    members.value = _memberMap.values.toList();
    if (isNew && id != deviceId && !host) events.add('$who слушает с вами');
  }

  void _memberLeft(String id) {
    final m = _memberMap.remove(id);
    members.value = _memberMap.values.toList();
    if (m != null && id != deviceId) events.add('${m.name} вышел');
  }

  // --- host -----------------------------------------------------------------------

  void _scheduleState() {
    _stateDebounce?.cancel();
    _stateDebounce = Timer(const Duration(milliseconds: 200), _publishState);
  }

  Future<void> _publishState() async {
    if (!isHost.value) return;
    final snap = player.snapshot();
    final queue = (snap['queue'] as List?) ?? const [];
    final index = snap['index'] as int? ?? -1;
    await _send('h', {
      'open': true,
      'host': name(),
      'track': index >= 0 && index < queue.length ? queue[index] : null,
      'next': [
        for (var i = index + 1; i < queue.length && i <= index + 15; i++)
          queue[i],
      ],
      'positionMs': snap['positionMs'],
      'durationMs': snap['durationMs'],
      // Guests play the very same YouTube version of imported songs.
      'matches': snap['matches'],
      'playing': snap['playing'] == true,
      'at': DateTime.now().millisecondsSinceEpoch,
    }, retain: true);
  }

  Future<void> _onSuggest(Map<String, dynamic> j) async {
    if (!_seen.add(j['id'] as String? ?? '')) return; // once per broker pair
    final t = Track.fromJson((j['track'] as Map).cast<String, dynamic>());
    await player.addNext(t);
    events.add('${j['from'] ?? 'Гость'} добавил «${t.title}»');
    _scheduleState();
  }

  // --- guest ----------------------------------------------------------------------

  void _onHostState(Map<String, dynamic> j) {
    if (j['open'] != true) {
      final who = hostName.value;
      unawaited(leave());
      events.add('$who завершил совместное прослушивание');
      return;
    }
    _hostState = j;
    _hostAt = DateTime.now();
    hostName.value = j['host'] as String? ?? 'Друг';
    upcoming.value = [
      for (final t in (j['next'] as List? ?? const []))
        Track.fromJson((t as Map).cast<String, dynamic>()),
    ];
    _follow();
  }

  bool _loading = false;

  /// Where the host is now, by our clock.
  Duration _hostPosition() {
    final j = _hostState!;
    final ms = j['positionMs'] as int? ?? 0;
    final moving = j['playing'] == true
        ? DateTime.now().difference(_hostAt).inMilliseconds
        : 0;
    return Duration(milliseconds: ms + moving);
  }

  /// Plays what the host plays, where the host is.
  Future<void> _follow() async {
    final j = _hostState;
    if (j == null || _loading) return;
    final track = j['track'] as Map?;
    if (track == null) return;
    final snap = player.snapshot();
    final queue = (snap['queue'] as List?) ?? const [];
    final index = snap['index'] as int? ?? -1;
    final mine = index >= 0 && index < queue.length
        ? queue[index] as Map
        : null;
    final hostPlaying = j['playing'] == true;
    if (mine == null ||
        mine['id'] != track['id'] ||
        mine['source'] != track['source']) {
      _loading = true;
      try {
        await player.restore({
          'queue': [track],
          'matches': j['matches'],
          'index': 0,
          // Loading takes a moment: aim a little ahead.
          'positionMs': _hostPosition().inMilliseconds + 800,
          'playing': hostPlaying,
        });
      } finally {
        // Give the stream time to start before checking drift.
        Future<void>.delayed(
          const Duration(seconds: 2),
          () => _loading = false,
        );
      }
      return;
    }
    final localPlaying = snap['playing'] == true;
    if (hostPlaying != localPlaying) {
      hostPlaying ? await player.play() : await player.pause();
    }
    final local = Duration(milliseconds: snap['positionMs'] as int? ?? 0);
    final drift = (local - _hostPosition()).inMilliseconds.abs();
    if (drift > 1200) {
      await player.seek(_hostPosition() + const Duration(milliseconds: 250));
    }
  }
}

/// Created in main() and overridden there.
final jamProvider = Provider<JamService>(
  (ref) => throw UnimplementedError('jamProvider is overridden in main()'),
);
