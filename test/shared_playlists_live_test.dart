// Live: two friends edit one playlist through the public relay brokers.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sync/shared_playlists.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: 'Song $id', artist: 'A');

Future<void> _until(bool Function() ok, {int seconds = 25}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  test('two friends edit one playlist', () async {
    final libA = LibraryStore.memory(), libB = LibraryStore.memory();
    final a = SharedPlaylists(library: libA, deviceName: () => 'Аня');
    final b = SharedPlaylists(library: libB, deviceName: () => 'Боря');
    await a.start();
    await b.start();
    final pa = libA.createPlaylist('Вечеринка');
    libA.addToPlaylist(pa, [_t('1'), _t('2')]);
    final code = await a.share(pa);

    // Boris joins with the code: he gets the songs.
    final pb = await b.join(code.toLowerCase());
    List<String> ids(LibraryStore l, String p) =>
        [for (final t in l.playlistTracks(p)) t.id];
    expect(ids(libB, pb), ['1', '2']);
    expect(libB.playlists().firstWhere((p) => p.id == pb).name, 'Вечеринка');

    // He adds a song: Anya sees it.
    libB.addToPlaylist(pb, [_t('3')]);
    await _until(() => ids(libA, pa).length == 3);
    expect(ids(libA, pa), ['1', '2', '3']);

    // She moves the new song to the top and removes one: he sees that.
    libA.movePlaylistItem(pa, libA.playlistTracks(pa), 2, 0);
    libA.removeFromPlaylist(pa, _t('2'));
    await _until(() => ids(libB, pb).join() == '31');
    // ignore: avoid_print
    print('SHARED A ${ids(libA, pa)} B ${ids(libB, pb)}');
    expect(ids(libB, pb), ['3', '1']);

    await a.dispose();
    await b.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
