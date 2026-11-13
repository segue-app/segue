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

import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../models/track.dart';
import 'relay.dart';

/// Playlists shared with friends: everyone who has the code adds,
/// removes and reorders songs, and everyone sees the same list.
///
/// Each shared playlist is a room on the public relay brokers, encrypted
/// with a key from its 8-character code (like listening together). Whoever
/// changes the playlist sends the whole list; the newest version wins.
class SharedPlaylists {
  SharedPlaylists({
    required this.library,
    required this.deviceName,
    this.brokers = Relay.defaultBrokers,
  }) {
    _load();
  }

  final LibraryStore library;
  final String Function() deviceName;
  final List<String> brokers;

  static const _meta = 'shared_playlists';
  static const _maxTracks = 1000;

  /// Playlist id → its share code.
  final codes = ValueNotifier<Map<String, String>>({});

  /// Versions: when each playlist last changed (ms), what we last sent
  /// or took (to tell our own edits from a friend's).
  final _at = <String, int>{};
  final _sig = <String, String>{};

  final _clients = <MqttServerClient>[];
  final _rooms = <String, ({String topic, SecretKey key})>{}; // by id
  StreamSubscription<void>? _libSub;
  Timer? _debounce;
  Completer<void>? _connecting;
  final _waiting = <String, Completer<Map<String, dynamic>>>{}; // by topic

  void _load() {
    try {
      final j = jsonDecode(library.getMeta(_meta) ?? '{}') as Map;
      final c = <String, String>{};
      j.forEach((id, v) {
        final m = (v as Map).cast<String, Object?>();
        c[id as String] = m['c'] as String;
        _at[id] = m['at'] as int? ?? 0;
        _sig[id] = m['sig'] as String? ?? '';
      });
      codes.value = c;
    } catch (_) {}
  }

  void _save() {
    library.setMeta(
      _meta,
      jsonEncode({
        for (final e in codes.value.entries)
          e.key: {
            'c': e.value,
            'at': _at[e.key] ?? 0,
            'sig': _sig[e.key] ?? '',
          },
      }),
    );
  }

  /// Connects when there's something shared (at start and after sharing).
  Future<void> start() async {
    _libSub ??= library.changes.listen((_) => _scheduleSend());
    if (codes.value.isEmpty) return;
    await _ensureConnected();
    for (final e in codes.value.entries) {
      await _open(e.key, e.value);
    }
    _scheduleSend(); // edits made while offline
  }

  bool isShared(String playlistId) => codes.value.containsKey(playlistId);

  /// Shares [playlistId]: returns the code friends join with.
  Future<String> share(String playlistId) async {
    final existing = codes.value[playlistId];
    if (existing != null) return existing;
    final code = Relay.randomId(8);
    await _ensureConnected();
    codes.value = {...codes.value, playlistId: code};
    _sig[playlistId] = '';
    _save();
    await _open(playlistId, code);
    await _send(playlistId);
    return code;
  }

  /// Joins a friend's playlist by code or segue://playlist link. Returns
  /// the id of the playlist created here.
  Future<String> join(String input) async {
    final uri = Uri.tryParse(input.trim());
    final raw = uri != null && uri.scheme == 'segue'
        ? uri.queryParameters['c'] ?? ''
        : input;
    final code = Relay.normalizeCode(raw);
    if (code == null) throw FormatException('Код из 8 букв и цифр'.tr);
    final already = codes.value.entries
        .where((e) => e.value == code)
        .map((e) => e.key)
        .firstOrNull;
    if (already != null) return already;
    await _ensureConnected();
    final (topic, key) = await Relay.codeKeys(code, 'playlist', 'segue/v1/sp');
    final got = _waiting[topic] = Completer<Map<String, dynamic>>();
    for (final c in _clients) {
      c.subscribe(topic, MqttQos.atLeastOnce);
    }
    _keysByTopic[topic] = key;
    final Map<String, dynamic> state;
    try {
      state = await got.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      for (final c in _clients) {
        c.unsubscribe(topic);
      }
      throw StateError('Плейлист не найден. Проверь код'.tr);
    } finally {
      _waiting.remove(topic);
    }
    final id = library.createPlaylist(state['name'] as String? ?? '');
    _rooms[id] = (topic: topic, key: key);
    codes.value = {...codes.value, id: code};
    _apply(id, state);
    return id;
  }

  /// This device stops taking part (the others keep the playlist).
  void stopSharing(String playlistId) {
    final room = _rooms.remove(playlistId);
    if (room != null) {
      for (final c in _clients) {
        c.unsubscribe(room.topic);
      }
    }
    codes.value = {...codes.value}..remove(playlistId);
    _at.remove(playlistId);
    _sig.remove(playlistId);
    _save();
  }

  /// "Join my playlist in Segue: segue://playlist?c=… (or code ABCD-EFGH)".
  static String invite(String name, String code) {
    final pretty = '${code.substring(0, 4)}-${code.substring(4)}';
    return 'Добавляй песни в мой плейлист «{0}» в Segue: {1} (или код {2})'
        .trArgs([name, 'segue://playlist?c=$code', pretty]);
  }

  // --- connection -------------------------------------------------------------

  final _keysByTopic = <String, SecretKey>{};

  Future<void> _ensureConnected() async {
    if (_clients.isNotEmpty) return;
    final busy = _connecting;
    if (busy != null) return busy.future;
    final done = _connecting = Completer<void>();
    try {
      await Future.wait([for (final h in brokers) _connect(h)]);
      if (_clients.isEmpty) throw StateError('Нет связи с интернетом'.tr);
    } finally {
      done.complete();
      _connecting = null;
    }
  }

  Future<void> _connect(String host) async {
    final id =
        'sgp-${library.deviceId.substring(0, 8)}-${Random().nextInt(1 << 30)}';
    final c = MqttServerClient.withPort(host, id, 8883)
      ..secure = true
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..logging(on: false);
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .startClean();
    try {
      await c.connect().timeout(const Duration(seconds: 12));
      _clients.add(c);
      c.updates!.listen(_onMessages);
    } catch (e) {
      debugPrint('shared playlists $host: $e');
      c.disconnect();
    }
  }

  Future<void> _open(String id, String code) async {
    final (topic, key) = await Relay.codeKeys(code, 'playlist', 'segue/v1/sp');
    _rooms[id] = (topic: topic, key: key);
    _keysByTopic[topic] = key;
    for (final c in _clients) {
      c.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  // --- sending and taking versions --------------------------------------------

  String _signature(String id) {
    final name =
        library.playlists().where((p) => p.id == id).firstOrNull?.name ?? '';
    return '$name\n${library.playlistTracks(id).map((t) => t.key).join('\n')}';
  }

  void _scheduleSend() {
    if (codes.value.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () async {
      for (final id in codes.value.keys.toList()) {
        // A playlist deleted here: this device leaves it.
        if (!library.playlists().any((p) => p.id == id)) {
          stopSharing(id);
          continue;
        }
        if (_signature(id) != _sig[id]) await _send(id);
      }
    });
  }

  Future<void> _send(String id) async {
    final room = _rooms[id];
    if (room == null || _clients.isEmpty) return;
    final playlist = library.playlists().where((p) => p.id == id).firstOrNull;
    if (playlist == null) return;
    final at = max(DateTime.now().millisecondsSinceEpoch, (_at[id] ?? 0) + 1);
    final body = {
      'name': playlist.name,
      'tracks': [
        for (final t in library.playlistTracks(id).take(_maxTracks)) t.toJson(),
      ],
      'at': at,
      'by': deviceName(),
    };
    final data = await Relay.seal(
      room.key,
      gzip.encode(utf8.encode(jsonEncode(body))),
    );
    for (final c in _clients) {
      if (c.connectionStatus?.state != MqttConnectionState.connected) continue;
      c.publishMessage(
        room.topic,
        MqttQos.atLeastOnce,
        Uint8Buffer()..addAll(data),
        retain: true,
      );
    }
    _at[id] = at;
    _sig[id] = _signature(id);
    _save();
  }

  Future<void> _onMessages(List<MqttReceivedMessage<MqttMessage>> batch) async {
    for (final m in batch) {
      final key = _keysByTopic[m.topic];
      if (key == null) continue;
      final data = (m.payload as MqttPublishMessage).payload.message.toList();
      if (data.isEmpty) continue;
      final plain = await Relay.open(key, data);
      if (plain == null) continue;
      Map<String, dynamic> j;
      try {
        j = jsonDecode(utf8.decode(gzip.decode(plain))) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final waiting = _waiting[m.topic];
      if (waiting != null && !waiting.isCompleted) {
        waiting.complete(j);
        continue;
      }
      final id = _rooms.entries
          .where((e) => e.value.topic == m.topic)
          .map((e) => e.key)
          .firstOrNull;
      if (id != null) _apply(id, j);
    }
  }

  /// Takes a friend's version if it's newer than what's here.
  void _apply(String id, Map<String, dynamic> j) {
    final at = j['at'] as int? ?? 0;
    if (at <= (_at[id] ?? 0)) return;
    final tracks = [
      for (final t in (j['tracks'] as List? ?? const []))
        Track.fromJson((t as Map).cast<String, dynamic>()),
    ];
    final name = j['name'] as String?;
    _at[id] = at;
    if (name != null && name.trim().isNotEmpty) {
      library.renamePlaylist(id, name);
    }
    library.replacePlaylistItems(id, tracks);
    // What's here now is that version: not an edit of ours to send back.
    _sig[id] = _signature(id);
    _save();
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _libSub?.cancel();
    for (final c in _clients) {
      c.disconnect();
    }
    _clients.clear();
  }
}

/// Which playlists are shared (rebuilds when that changes).
final sharedCodesProvider = Provider<Map<String, String>>((ref) {
  final s = ref.watch(sharedPlaylistsProvider);
  void changed() => ref.invalidateSelf();
  s.codes.addListener(changed);
  ref.onDispose(() => s.codes.removeListener(changed));
  return s.codes.value;
});

/// Created in main() and overridden there.
final sharedPlaylistsProvider = Provider<SharedPlaylists>(
  (ref) => throw UnimplementedError(
    'sharedPlaylistsProvider is overridden in main()',
  ),
);
