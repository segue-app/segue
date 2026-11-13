import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/car_browser.dart';

Track _t(String id, [String artist = 'A']) =>
    Track(id: id, source: SourceKind.youtube, title: id, artist: artist);

void main() {
  test('the car sees the wave, liked songs, playlists and recent plays', () async {
    final lib = LibraryStore.memory();
    lib.likeMany([_t('a'), _t('b', 'Ля')]);
    final p = lib.createPlaylist('Дорога');
    lib.addToPlaylist(p, [_t('x'), _t('y')]);
    lib.recordPlay(_t('x'));
    final played = <String>[];
    var waves = 0;
    final car = CarBrowser(
      library: lib,
      playList: (list, start, {context}) async =>
          played.add('${list[start].id} of ${list.length} ($context)'),
      startWave: () async => waves++,
      search: (q) async => [_t('web $q')],
    );

    final root = await car.children(AudioService.browsableRootId);
    expect(root.map((m) => m.id), ['wave', 'liked', 'playlists', 'history']);
    expect(root.first.playable, isTrue);
    expect(root[1].playable, isFalse);

    final liked = await car.children('liked');
    expect(liked.map((m) => m.title).toSet(), {'a', 'b'});
    expect(liked.every((m) => m.playable == true), isTrue);

    final lists = await car.children('playlists');
    expect(lists.single.title, 'Дорога');
    final songs = await car.children(lists.single.id);
    expect(songs.map((m) => m.title), ['x', 'y']);
    expect(songs.last.id, 'pl|$p|${_t('y').key}');

    expect((await car.children('history')).single.title, 'x');
    expect((await car.children(AudioService.recentRootId)).single.title, 'x');

    final found = await car.find('ля');
    expect(found.map((m) => m.title), ['b', 'web ля']);

    await car.play('wave');
    expect(waves, 1);
    await car.play(songs.last.id);
    await car.play(liked.first.id);
    await car.play(found.last.id);
    expect(played, [
      'y of 2 (playlist:$p)',
      '${liked.first.title} of 2 (liked)',
      'web ля of 2 (null)',
    ]);
  });
}
