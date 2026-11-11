import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/local/local_library.dart';
import 'package:segue/core/models/track.dart';

void main() {
  late Directory music, covers;
  late LibraryStore store;
  late LocalLibrary local;

  setUp(() {
    music = Directory.systemTemp.createTempSync('segue_music');
    covers = Directory.systemTemp.createTempSync('segue_covers');
    store = LibraryStore.memory();
    local = LocalLibrary(store, coversDir: covers);
  });
  tearDown(() {
    music.deleteSync(recursive: true);
    covers.deleteSync(recursive: true);
  });

  test('indexes audio files, reads names when tags are missing', () async {
    Directory('${music.path}/Album').createSync();
    File('${music.path}/Daft Punk - Get Lucky.mp3')
        .writeAsBytesSync(List.filled(64, 0));
    File('${music.path}/Album/intro.flac').writeAsBytesSync(List.filled(64, 0));
    File('${music.path}/notes.txt').writeAsStringSync('not music');
    store.addFolder(music.path);

    expect(await local.scan(music.path), 2);
    final tracks = store.localTracks();
    expect(tracks.every((t) => t.source == SourceKind.local), isTrue);
    final lucky = tracks.firstWhere((t) => t.title == 'Get Lucky');
    expect(lucky.artist, 'Daft Punk');
    expect(lucky.id, endsWith('Daft Punk - Get Lucky.mp3'));
    // No artist anywhere: the folder name stands in.
    expect(tracks.firstWhere((t) => t.title == 'intro').artist, isNotEmpty);
  });

  test(
    'rescan drops deleted files and removing the folder clears it',
    () async {
      final f = File('${music.path}/A - B.mp3')
        ..writeAsBytesSync(List.filled(64, 0));
      store.addFolder(music.path);
      await local.scan(music.path);
      expect(store.localTracks(), hasLength(1));

      f.deleteSync();
      await local.scan(music.path);
      expect(store.localTracks(), isEmpty);

      File('${music.path}/C - D.mp3').writeAsBytesSync(List.filled(64, 0));
      await local.scan(music.path);
      local.removeFolder(music.path);
      expect(store.localTracks(), isEmpty);
      expect(store.folders(), isEmpty);
    },
  );

  test('local source plays files and refuses missing ones', () async {
    final f = File('${music.path}/X - Y.mp3')
      ..writeAsBytesSync(List.filled(64, 0));
    final t = Track(
      id: f.path,
      source: SourceKind.local,
      title: 'Y',
      artist: 'X',
    );
    final info = await LocalSource().resolveStream(t);
    expect(info.url.isScheme('file'), isTrue);
    f.deleteSync();
    expect(() => LocalSource().resolveStream(t), throwsStateError);
  });
}
