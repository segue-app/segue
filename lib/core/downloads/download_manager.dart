import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../sources/music_source.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Saves tracks to the device for offline listening.
///
/// One file per track in the app's data folder, recorded in the library so
/// the player picks it up instead of streaming. Two downloads at a time;
/// the rest wait in a queue.
class DownloadManager {
  DownloadManager({
    required this.library,
    required this.sources,
    http.Client? client,
    Directory? directory,
  }) : _http = client ?? http.Client(),
       _dir = directory;

  final LibraryStore library;
  final Map<SourceKind, MusicSource> sources;
  final http.Client _http;

  /// Track key → progress 0..1 while downloading or queued (0).
  final progress = ValueNotifier<Map<String, double>>({});

  /// Human-readable failures ("Не удалось скачать …").
  final errors = StreamController<String>.broadcast();

  final _queue = <Track>[];
  int _running = 0;
  static const _parallel = 2;
  Directory? _dir;

  /// Completes when nothing is queued or downloading.
  Future<void> get idle async {
    while (progress.value.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<Directory> _folder() async => _dir ??= Directory(
    '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}downloads',
  )..createSync(recursive: true);

  bool isDownloaded(Track t) =>
      t.source == SourceKind.local || library.downloadedPath(t) != null;

  /// Queues [tracks] that aren't on the device yet.
  void download(List<Track> tracks) {
    final busy = progress.value;
    var added = false;
    for (final t in tracks) {
      if (isDownloaded(t) || busy.containsKey(t.key)) continue;
      if (sources[t.source] is! FileSource) continue;
      _queue.add(t);
      busy[t.key] = 0;
      added = true;
    }
    if (!added) return;
    progress.value = {...busy};
    _pump();
  }

  void _pump() {
    while (_running < _parallel && _queue.isNotEmpty) {
      final t = _queue.removeAt(0);
      _running++;
      unawaited(
        _download(t).whenComplete(() {
          _running--;
          progress.value = {...progress.value}..remove(t.key);
          _pump();
        }),
      );
    }
  }

  /// Removes the file and forgets it.
  Future<void> delete(Track t) async {
    final path = library.downloadedPath(t);
    library.removeDownload(t);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> deleteAll() async {
    for (final t in library.downloadedTracks()) {
      await delete(t);
    }
  }

  void _report(Track t, double p) {
    if (!progress.value.containsKey(t.key)) return;
    progress.value = {...progress.value, t.key: p.clamp(0.0, 1.0)};
  }

  Future<void> _download(Track t) async {
    try {
      final out = await fetchTo(t, await _folder(), (p) => _report(t, p));
      library.saveDownload(t, out.path, out.lengthSync());
    } catch (e) {
      debugPrint('download ${t.title} failed: $e');
      errors.add('Не удалось скачать «{0}»'.trArgs([t.title]));
    }
  }

  /// Fetches [t]'s whole audio file into [dir] (named after the track).
  Future<File> fetchTo(
    Track t,
    Directory dir, [
    void Function(double)? onProgress,
  ]) async {
    final name = sha1.convert(utf8.encode(t.key)).toString();
    final tmp = File('${dir.path}${Platform.pathSeparator}$name.part');
    try {
      final info = await (sources[t.source]! as FileSource).resolveFile(t);
      final String ext;
      if (info.hls) {
        ext = await _hls(info.url, tmp, onProgress ?? (_) {});
      } else {
        await _file(info, tmp, onProgress ?? (_) {});
        ext = _extFor(info.mimeType, info.url);
      }
      final out = File('${dir.path}${Platform.pathSeparator}$name.$ext');
      if (out.existsSync()) out.deleteSync();
      await tmp.rename(out.path);
      return out;
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  final _seekCache = <String, Future<String>>{};

  /// A temporary whole-file copy of an HLS stream, for seeking: libmpv can't
  /// seek SoundCloud's fMP4 HLS, but seeks the stitched file fine. Kept in
  /// the system temp folder, not in the library; one per track per session.
  Future<String> seekableCopy(StreamInfo info, Track t) => _seekCache[t.key] ??=
      () async {
        final dir = Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}segue_seek',
        )..createSync(recursive: true);
        final name = sha1.convert(utf8.encode(t.key)).toString();
        final tmp = File('${dir.path}${Platform.pathSeparator}$name.part');
        final ext = await _hls(info.url, tmp, (_) {});
        final out = File('${dir.path}${Platform.pathSeparator}$name.$ext');
        await tmp.rename(out.path);
        return out.path;
      }().catchError((Object e) {
        _seekCache.remove(t.key);
        throw e;
      });

  static String _extFor(String? mime, Uri url) {
    final m = mime ?? '';
    if (m.contains('mp4') || m.contains('m4a') || m.contains('aac')) {
      return 'm4a';
    }
    if (m.contains('mpeg') || m.contains('mp3')) return 'mp3';
    if (m.contains('webm')) return 'webm';
    if (m.contains('ogg') || m.contains('opus')) return 'ogg';
    final path = url.path.toLowerCase();
    for (final e in ['mp3', 'm4a', 'ogg', 'opus', 'flac']) {
      if (path.endsWith('.$e')) return e;
    }
    return 'mp3';
  }

  /// A single file, in ~1 MB range requests (YouTube refuses bigger ones).
  Future<void> _file(
    StreamInfo info,
    File out,
    void Function(double) onProgress,
  ) async {
    final sink = out.openWrite();
    try {
      final total = info.contentLength;
      if (total == null) {
        final res = await _http
            .get(info.url)
            .timeout(const Duration(minutes: 5));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}');
        }
        sink.add(res.bodyBytes);
        onProgress(1);
        return;
      }
      const chunk = 1024 * 1024;
      var pos = 0;
      while (pos < total) {
        final end = (pos + chunk).clamp(0, total) - 1;
        List<int>? bytes;
        for (var attempt = 0; attempt < 3 && bytes == null; attempt++) {
          try {
            final res = await _http
                .get(info.url, headers: {'Range': 'bytes=$pos-$end'})
                .timeout(const Duration(seconds: 30));
            if (res.statusCode == 200 || res.statusCode == 206) {
              bytes = res.bodyBytes;
            }
          } catch (_) {}
        }
        if (bytes == null || bytes.isEmpty) {
          throw HttpException('range $pos-$end failed');
        }
        sink.add(bytes);
        pos += bytes.length;
        onProgress(pos / total);
      }
    } finally {
      await sink.close();
    }
  }

  /// Joins an HLS playlist's segments into one file. MP3 segments join into
  /// a valid MP3; fMP4 (with an init segment) into a valid M4A.
  Future<String> _hls(
    Uri playlist,
    File out,
    void Function(double) onProgress,
  ) async {
    final res = await _http.get(playlist).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpException('playlist ${res.statusCode}');
    }
    final lines = const LineSplitter().convert(res.body);
    // A master playlist: follow its first variant.
    final variant = lines
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .firstOrNull;
    if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF')) &&
        variant != null) {
      return _hls(playlist.resolve(variant), out, onProgress);
    }
    final map = RegExp(r'#EXT-X-MAP:URI="([^"]+)"')
        .firstMatch(res.body)
        ?.group(1);
    final segments = [
      for (final l in lines)
        if (l.isNotEmpty && !l.startsWith('#')) playlist.resolve(l),
    ];
    if (segments.isEmpty) throw StateError('empty playlist');

    final sink = out.openWrite();
    var ext = map != null ? 'm4a' : 'mp3';
    try {
      if (map != null) sink.add(await _get(playlist.resolve(map)));
      for (var i = 0; i < segments.length; i++) {
        final bytes = await _get(segments[i]);
        // MPEG-TS segments (0x47 sync byte) would need remuxing.
        if (i == 0 && map == null && bytes.isNotEmpty && bytes.first == 0x47) {
          ext = 'ts';
        }
        sink.add(bytes);
        onProgress((i + 1) / segments.length);
      }
    } finally {
      await sink.close();
    }
    return ext;
  }

  Future<List<int>> _get(Uri url) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await _http.get(url).timeout(const Duration(seconds: 30));
        if (r.statusCode == 200) return r.bodyBytes;
      } catch (_) {}
    }
    throw HttpException('segment failed: $url');
  }

  void dispose() {
    _http.close();
    errors.close();
  }
}
