import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: 'Song $id', artist: 'A');

/// One sync round both ways, the way the network sync does it.
void _sync(LibraryStore a, LibraryStore b, Map<String, int> cursors) {
  final fromA = a.exportChanges(cursors['a'] ?? 0);
  final fromB = b.exportChanges(cursors['b'] ?? 0);
  b.applyChanges(fromA);
  a.applyChanges(fromB);
  cursors['a'] = fromA['seq']! as int;
  cursors['b'] = fromB['seq']! as int;
}

void main() {
  late LibraryStore phone, laptop;
  final cursors = <String, int>{};
  setUp(() {
    phone = LibraryStore.memory();
    laptop = LibraryStore.memory();
    cursors.clear();
  });

  test('likes, playlists and history reach the other device', () {
    phone.setLiked(_t('1'), true);
    final pid = phone.createPlaylist('Gym');
    phone.addToPlaylist(pid, [_t('2'), _t('3')]);
    laptop.recordPlay(_t('9'));
    _sync(phone, laptop, cursors);

    expect(laptop.likedKeys(), {'youtube:1'});
    expect(laptop.playlists().single.name, 'Gym');
    expect(laptop.playlistTracks(pid).map((t) => t.id), ['2', '3']);
    expect(phone.recentlyPlayed().map((t) => t.id), ['9']);
  });

  test('deletes propagate and the newest change wins', () async {
    phone.setLiked(_t('1'), true);
    final pid = phone.createPlaylist('Old name');
    _sync(phone, laptop, cursors);

    laptop.setLiked(_t('1'), false); // unliked on the laptop
    // Edits a real moment apart: each store's clock may run a few ms ahead
    // of the wall clock after a burst of writes (it never goes back).
    await Future<void>.delayed(const Duration(milliseconds: 30));
    laptop.renamePlaylist(pid, 'Laptop name');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    phone.renamePlaylist(pid, 'Phone name'); // later edit wins
    _sync(phone, laptop, cursors);

    expect(phone.likedKeys(), isEmpty);
    expect(phone.playlists().single.name, 'Phone name');
    expect(laptop.playlists().single.name, 'Phone name');

    laptop.deletePlaylist(pid);
    _sync(phone, laptop, cursors);
    expect(phone.playlists(), isEmpty);
  });

  test('second sync sends only new changes and converges', () {
    phone.setLiked(_t('1'), true);
    _sync(phone, laptop, cursors);
    final again = phone.exportChanges(cursors['a']!);
    expect((again['likes']! as List), isEmpty);

    // A third device's change relayed through the laptop still arrives.
    final tablet = LibraryStore.memory();
    tablet.setLiked(_t('7'), true);
    laptop.applyChanges(tablet.exportChanges(0));
    _sync(phone, laptop, cursors);
    expect(phone.likedKeys(), {'youtube:1', 'youtube:7'});
  });
}
