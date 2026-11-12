import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: id, artist: 'A');

void main() {
  test('moving songs in a playlist keeps the new order', () {
    final lib = LibraryStore.memory();
    final p = lib.createPlaylist('P');
    lib.addToPlaylist(p, [_t('a'), _t('b'), _t('c'), _t('d')]);
    List<String> ids() => [for (final t in lib.playlistTracks(p)) t.id];
    lib.movePlaylistItem(p, lib.playlistTracks(p), 0, 2); // a → after c
    expect(ids(), ['b', 'c', 'a', 'd']);
    lib.movePlaylistItem(p, lib.playlistTracks(p), 3, 0); // d → first
    expect(ids(), ['d', 'b', 'c', 'a']);
    lib.movePlaylistItem(p, lib.playlistTracks(p), 1, 3); // b → last
    expect(ids(), ['d', 'c', 'a', 'b']);
  });

  test('liked songs can be put in any order, even after a bulk import', () {
    final lib = LibraryStore.memory();
    // Imported together: like times one apart, no room between them.
    lib.likeMany([_t('a'), _t('b'), _t('c'), _t('d')]);
    List<String> ids() => [for (final t in lib.likedTracks()) t.id];
    final start = ids();
    lib.moveLiked(lib.likedTracks(), 0, 2);
    expect(ids(), [start[1], start[2], start[0], start[3]]);
    lib.moveLiked(lib.likedTracks(), 3, 1);
    expect(ids(), [start[1], start[3], start[2], start[0]]);
    lib.moveLiked(lib.likedTracks(), 1, 0);
    expect(ids(), [start[3], start[1], start[2], start[0]]);
  });
}
