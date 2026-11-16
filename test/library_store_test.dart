import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id, {String title = 'Song'}) => Track(
  id: id,
  source: SourceKind.youtube,
  title: '$title $id',
  artist: 'Artist',
);

void main() {
  late LibraryStore store;
  setUp(() => store = LibraryStore.memory());
  tearDown(() => store.dispose());

  test('like, unlike, re-like keeps newest first', () {
    store.setLiked(_t('a'), true);
    store.setLiked(_t('b'), true);
    expect(store.likedTracks().map((t) => t.id), ['b', 'a']);
    store.setLiked(_t('a'), false);
    expect(store.isLiked(_t('a')), isFalse);
    expect(store.likedKeys(), {'youtube:b'});
    store.setLiked(_t('a'), true);
    expect(store.likedTracks().first.id, 'a');
  });

  test('playlists: add keeps order, skips duplicates, soft-deletes', () {
    final id = store.createPlaylist('Road');
    expect(store.addToPlaylist(id, [_t('1'), _t('2')]), 2);
    expect(store.addToPlaylist(id, [_t('2'), _t('3')]), 1);
    expect(store.playlistTracks(id).map((t) => t.id), ['1', '2', '3']);

    store.removeFromPlaylist(id, _t('2'));
    expect(store.playlistTracks(id).map((t) => t.id), ['1', '3']);
    expect(store.playlists().single.count, 2);

    // Re-adding a removed track puts it at the end.
    store.addToPlaylist(id, [_t('2')]);
    expect(store.playlistTracks(id).map((t) => t.id), ['1', '3', '2']);

    store.renamePlaylist(id, 'Night');
    expect(store.playlists().single.name, 'Night');
    store.deletePlaylist(id);
    expect(store.playlists(), isEmpty);
  });

  test('history: unique tracks, most recent first', () async {
    store.recordPlay(_t('x'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    store.recordPlay(_t('y'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    store.recordPlay(_t('x'));
    expect(store.recentlyPlayed().map((t) => t.id), ['x', 'y']);
    // The history screen: each song once, with when it last played.
    final h = store.listeningHistory();
    expect(h.map((e) => e.$1.id), ['x', 'y']);
    expect(h.first.$2.isAfter(h.last.$2) || h.first.$2 == h.last.$2, isTrue);
    store.removeFromHistory(_t('x'));
    expect(store.listeningHistory().map((e) => e.$1.id), ['y']);
    store.clearHistory();
    expect(store.recentlyPlayed(), isEmpty);
  });

  test('changes stream fires on writes', () async {
    final events = <void>[];
    final sub = store.changes.listen(events.add);
    store.setLiked(_t('a'), true);
    store.createPlaylist('P');
    await Future<void>.delayed(Duration.zero);
    expect(events.length, 2);
    await sub.cancel();
  });

  test('rows from before change numbers still sync', () {
    final store = LibraryStore.memory();
    const t = Track(
      id: 'old',
      source: SourceKind.youtube,
      title: 'Old',
      artist: 'A',
    );
    store.setLiked(t, true);
    // Simulate a library from the first versions: no change numbers.
    store.debugExecute('UPDATE likes SET seq = 0');
    store.debugExecute('UPDATE tracks SET seq = 0');
    final all = store.exportChanges(0);
    expect((all['likes']! as List), hasLength(1));
    final other = LibraryStore.memory()
      ..applyChanges(all.cast<String, dynamic>());
    expect(other.isLiked(t), isTrue);
  });

  test('keyed store: get, put, trim, and old blobs move in', () {
    final s = LibraryStore.memory();
    s.setMeta('loudness', '{"youtube:a": -3.5, "youtube:b": 1.0}');
    // As on an old install: the next open moves the blob into rows.
    s.debugExecute('DELETE FROM kv');
    s.debugMigrateBlobs();
    expect(s.kvGet('loud', 'youtube:a'), -3.5);
    expect(s.getMeta('loudness'), isNull);

    for (var i = 0; i < 250; i++) {
      s.kvPut('match', 'k$i', {'id': '$i'}, keep: 120);
    }
    expect(s.kvGet('match', 'k249'), {'id': '249'});
    // Trimmed every 100 writes to the newest 120.
    expect(s.kvGet('match', 'k0'), isNull);
    s.kvRemove('match', 'k249');
    expect(s.kvGet('match', 'k249'), isNull);
  });

  test('change kinds tell plays from edits', () async {
    final s = LibraryStore.memory();
    final kinds = <LibChange>[];
    final sub = s.changeKinds.listen(kinds.add);
    s.recordPlay(_t('1'));
    s.setLiked(_t('1'), true);
    await Future<void>.delayed(Duration.zero);
    expect(kinds, [LibChange.history, LibChange.edit]);
    await sub.cancel();
  });
}
