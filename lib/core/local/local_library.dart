import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path_provider/path_provider.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../sources/music_source.dart';

import 'package:segue/core/l10n/l10n.dart';

const audioExtensions = {
  'mp3',
  'flac',
  'm4a',
  'aac',
  'ogg',
  'opus',
  'wav',
  'aiff',
  'aif',
  'alac',
  'wma',
};

/// The user's own music: folders they add, indexed with tags and covers.
class LocalLibrary {
  LocalLibrary(this.library, {Directory? coversDir}) : _covers = coversDir;

  final LibraryStore library;

  /// Folder being scanned and how far along (0..1); null when idle.
  final scanning = ValueNotifier<({String folder, double progress})?>(null);

  Directory? _covers;

  /// Re-opens access to saved folders (macOS keeps access only through
  /// security-scoped bookmarks) and rescans them in the background.
  Future<void> start() async {
    _covers = Directory(
      '${(await getApplicationSupportDirectory()).path}/covers',
    )..createSync(recursive: true);
    for (final f in library.folders()) {
      if (Platform.isMacOS && f.bookmark != null) {
        try {
          final dir = await SecureBookmarks().resolveBookmark(
            f.bookmark!,
            isDirectory: true,
          );
          await SecureBookmarks().startAccessingSecurityScopedResource(dir);
        } catch (_) {}
      }
    }
    for (final f in library.folders()) {
      await scan(f.path);
    }
  }

  /// Asks for a folder, remembers it and indexes it. Returns its path.
  Future<String?> addFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Папка с музыкой'.tr,
    );
    if (path == null) return null;
    String? bookmark;
    if (Platform.isMacOS) {
      try {
        bookmark = await SecureBookmarks().bookmark(Directory(path));
      } catch (_) {}
    }
    library.addFolder(path, bookmark: bookmark);
    await scan(path);
    return path;
  }

  void removeFolder(String path) => library.removeFolder(path);

  /// Indexes audio files under [folder]; unchanged files are reused.
  Future<int> scan(String folder) async {
    final covers = _covers ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/covers',
    )..createSync(recursive: true);
    scanning.value = (folder: folder, progress: 0);
    try {
      final known = library.localFileTimes(folder);
      final existing = {for (final t in library.localTracks()) t.id: t};
      final files = await Isolate.run(() => _listAudio(folder));
      final result = <String, (Track, int)>{};
      final toRead = <String>[];
      for (final (path, mtime) in files) {
        final old = existing[path];
        if (known[path] == mtime && old != null) {
          result[path] = (old, mtime);
        } else {
          toRead.add(path);
        }
      }
      // Read tags in batches off the UI thread.
      for (var i = 0; i < toRead.length; i += 40) {
        final batch = toRead.sublist(i, (i + 40).clamp(0, toRead.length));
        final coverDir = covers.path;
        final read = await Isolate.run(
          () => [for (final p in batch) _readTrack(p, folder, coverDir)],
        );
        for (final r in read) {
          final track = Track.fromJson(
            jsonDecode(r.$1) as Map<String, dynamic>,
          );
          result[track.id] = (track, r.$2);
        }
        scanning.value = (
          folder: folder,
          progress: (i + batch.length) / toRead.length,
        );
      }
      library.replaceLocalFiles(folder, result);
      return result.length;
    } finally {
      scanning.value = null;
    }
  }
}

/// (path, mtime ms) of every audio file under [folder].
List<(String, int)> _listAudio(String folder) {
  final out = <(String, int)>[];
  try {
    for (final e in Directory(
      folder,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final ext = e.path.split('.').last.toLowerCase();
      if (!audioExtensions.contains(ext)) continue;
      out.add((e.path, e.statSync().modified.millisecondsSinceEpoch));
    }
  } catch (_) {}
  return out;
}

/// Reads one file's tags; saves the embedded cover next to the app's data.
/// Returns (track json, mtime). Runs in an isolate.
(String, int) _readTrack(String path, String folder, String coverDir) {
  final file = File(path);
  final mtime = file.statSync().modified.millisecondsSinceEpoch;
  final name = path.split(Platform.pathSeparator).last;
  final base = name.contains('.')
      ? name.substring(0, name.lastIndexOf('.'))
      : name;
  String? title, artist, cover;
  Duration? duration;
  try {
    final meta = readMetadata(file, getImage: true);
    title = meta.title;
    artist = meta.artist ?? meta.albumArtist;
    duration = meta.duration;
    if (meta.pictures.isNotEmpty) {
      final pic = meta.pictures.first;
      final ext = pic.mimetype.contains('png') ? 'png' : 'jpg';
      final out = File('$coverDir/${sha1.convert(utf8.encode(path))}.$ext');
      if (!out.existsSync()) out.writeAsBytesSync(pic.bytes);
      cover = out.path;
    }
  } catch (_) {}
  // No tags: "Artist - Title.mp3" is the common naming.
  if (title == null || title.trim().isEmpty) {
    final dash = base.indexOf(' - ');
    if (dash > 0) {
      artist ??= base.substring(0, dash).trim();
      title = base.substring(dash + 3).trim();
    } else {
      title = base;
    }
  }
  final track = Track(
    id: path,
    source: SourceKind.local,
    title: title,
    artist: (artist == null || artist.trim().isEmpty)
        ? folder.split(Platform.pathSeparator).last
        : artist.trim(),
    artworkUrl: cover,
    duration: duration,
  );
  return (jsonEncode(track.toJson()), mtime);
}

/// Plays files from the user's folders.
class LocalSource implements MusicSource {
  @override
  SourceKind get kind => SourceKind.local;

  @override
  String get label => 'На устройстве'.tr;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async => const [];

  @override
  Future<StreamInfo> resolveStream(Track track) async {
    if (!File(track.id).existsSync()) {
      throw StateError('Файл не найден: {0}'.trArgs([track.id]));
    }
    return StreamInfo(Uri.file(track.id), duration: track.duration);
  }
}
