// Live: downloads real tracks (no playback). Run: flutter test --tags live
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/downloads/download_manager.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

/// First bytes of a real audio file: MP4 'ftyp', ID3 tag or an MPEG frame.
String kindOf(List<int> b) {
  if (b.length > 8 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
    return 'm4a';
  }
  if (String.fromCharCodes(b.take(3)) == 'ID3') return 'mp3';
  if (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return 'mp3';
  return 'unknown';
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('segue_dl'));
  tearDown(() => dir.deleteSync(recursive: true));

  for (final source in <MusicSource>[YouTubeSource(), SoundCloudSource()]) {
    test('${source.label}: downloads a whole playable file', () async {
      final library = LibraryStore.memory();
      final dm = DownloadManager(
        library: library,
        sources: {source.kind: source},
        directory: dir,
      );
      final track = (await source.search('miyagi фея', limit: 3)).first;
      dm.download([track]);
      await dm.idle.timeout(const Duration(minutes: 2));
      final path = library.downloadedPath(track);
      expect(path, isNotNull, reason: 'download failed');
      final file = File(path!);
      final head = file.openSync().readSync(16);
      // ignore: avoid_print
      print(
        '${source.label}: ${track.title} → ${file.uri.pathSegments.last}, '
        '${(file.lengthSync() / 1e6).toStringAsFixed(1)} MB, ${kindOf(head)}',
      );
      expect(file.lengthSync(), greaterThan(500 * 1024));
      expect(kindOf(head), isNot('unknown'));
      await dm.delete(track);
      expect(file.existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
