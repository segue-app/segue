import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import '../sources/music_source.dart';
import 'download_manager.dart';

/// Keeps the songs you've been listening to on the device, by itself:
/// they start at once and play without internet. Separate from the songs
/// downloaded on purpose; the oldest go when it's full.
///
/// A song is kept once it has played for half a minute (skipped ones
/// aren't worth the space). Phones only fetch over Wi-Fi.
class AudioCache {
  AudioCache({
    required this.library,
    required this.downloads,
    required this.sources,
    Directory? directory,
  }) : _dir = directory {
    _entries.length; // load now: Settings shows the size from the start
  }

  final LibraryStore library;
  final DownloadManager downloads;
  final Map<SourceKind, MusicSource> sources;

  bool enabled = true;
  static const maxTracks = 100;
  static const maxBytes = 1500 * 1024 * 1024;

  Directory? _dir;
  final _fetching = <String>{};
  Timer? _listened, _save;

  /// Track key → (file, size, last played ms).
  late final Map<String, ({String path, int size, int at})> _entries = _load();

  /// Size on disk, for Settings.
  final bytes = ValueNotifier<int>(0);

  Map<String, ({String path, int size, int at})> _load() {
    final out = <String, ({String path, int size, int at})>{};
    try {
      final j = jsonDecode(library.getMeta('audio_cache') ?? '{}') as Map;
      j.forEach((k, v) {
        final m = (v as Map).cast<String, Object?>();
        out[k as String] = (
          path: m['p'] as String,
          size: m['s'] as int,
          at: m['a'] as int,
        );
      });
    } catch (_) {}
    bytes.value = out.values.fold(0, (n, e) => n + e.size);
    return out;
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () {
      library.setMeta(
        'audio_cache',
        jsonEncode({
          for (final e in _entries.entries)
            e.key: {'p': e.value.path, 's': e.value.size, 'a': e.value.at},
        }),
      );
    });
    bytes.value = _entries.values.fold(0, (n, e) => n + e.size);
  }

  Future<Directory> _folder() async => _dir ??= Directory(
    '${(await getApplicationSupportDirectory()).path}'
    '${Platform.pathSeparator}cache_audio',
  )..createSync(recursive: true);

  /// The kept file for [t], if there is one (and marks it as used).
  String? pathFor(Track t) {
    final e = _entries[t.key];
    if (e == null) return null;
    if (!File(e.path).existsSync()) {
      _entries.remove(t.key);
      _persist();
      return null;
    }
    _entries[t.key] = (
      path: e.path,
      size: e.size,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    _persist();
    return e.path;
  }

  bool contains(Track t) => _entries.containsKey(t.key);

  /// Watches what plays and keeps songs listened to for 30 s.
  void attach(SegueAudioHandler player) {
    player.mediaItem.listen((_) {
      _listened?.cancel();
      final t = player.current;
      if (t == null) return;
      _listened = Timer(const Duration(seconds: 30), () {
        if (player.current?.key == t.key &&
            player.isPlaying &&
            player.output.value == null) {
          unawaited(keep(t));
        }
      });
    });
  }

  /// Fetches [t] into the cache (if worth it and allowed now).
  Future<void> keep(Track t) async {
    if (!enabled ||
        t.source == SourceKind.local ||
        contains(t) ||
        library.downloadedPath(t) != null ||
        sources[t.source] is! FileSource ||
        !_fetching.add(t.key)) {
      return;
    }
    try {
      if (!await _onUnmeteredNetwork()) return;
      final file = await downloads.fetchTo(t, await _folder());
      _entries[t.key] = (
        path: file.path,
        size: file.lengthSync(),
        at: DateTime.now().millisecondsSinceEpoch,
      );
      _evict();
      _persist();
    } catch (e) {
      debugPrint('cache ${t.title}: $e');
    } finally {
      _fetching.remove(t.key);
    }
  }

  /// Oldest first until under both limits.
  void _evict() {
    final byAge = _entries.entries.toList()
      ..sort((a, b) => a.value.at.compareTo(b.value.at));
    var total = byAge.fold(0, (n, e) => n + e.value.size);
    var count = byAge.length;
    for (final e in byAge) {
      if (count <= maxTracks && total <= maxBytes) break;
      try {
        File(e.value.path).deleteSync();
      } catch (_) {}
      _entries.remove(e.key);
      total -= e.value.size;
      count--;
    }
  }

  Future<void> clear() async {
    for (final e in _entries.values) {
      try {
        await File(e.path).delete();
      } catch (_) {}
    }
    _entries.clear();
    _persist();
  }

  /// Computers: always. Phones: only on Wi-Fi (an interface like wlan0
  /// or en0 with an address), so the cache never eats mobile data.
  static Future<bool> _onUnmeteredNetwork() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return ifs.any(
        (i) => i.name.startsWith('wlan') || (Platform.isIOS && i.name == 'en0'),
      );
    } catch (_) {
      return false;
    }
  }
}

/// Created in main() and overridden there.
final audioCacheProvider = Provider<AudioCache>(
  (ref) => throw UnimplementedError('audioCacheProvider is overridden in main()'),
);
