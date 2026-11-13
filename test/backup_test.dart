import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/catalog/taste.dart';
import 'package:segue/core/library/backup.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id, [String artist = 'A']) =>
    Track(id: id, source: SourceKind.youtube, title: id, artist: artist);

void main() {
  test('a backup brings likes, playlists, history, settings and taste back', () {
    final a = LibraryStore.memory();
    a.likeMany([_t('a'), _t('b'), _t('c')]);
    a.moveLiked(a.likedTracks(), 0, 2);
    final p = a.createPlaylist('Дорога');
    a.addToPlaylist(p, [_t('x'), _t('y')]);
    a.recordPlay(_t('x'));
    a.setMeta('appearance', jsonEncode({'accent': 3, 'textScale': 1.2}));
    a.touchPrefs();
    final tasteA = Taste(a)..dislike(_t('bad', 'Noise'));
    final file = Backup.encode(a, taste: tasteA);

    final b = LibraryStore.memory();
    b.setMeta('appearance', jsonEncode({'accent': 1, 'textScale': 0.9}));
    final tasteB = Taste(b);
    final s = Backup.restore(b, Backup.decode(file), taste: tasteB);

    expect(s.liked, 3);
    expect(s.playlists, 1);
    expect([for (final t in b.likedTracks()) t.id],
        [for (final t in a.likedTracks()) t.id]);
    final pb = b.playlists().single;
    expect(pb.name, 'Дорога');
    expect([for (final t in b.playlistTracks(pb.id)) t.id], ['x', 'y']);
    expect(b.recentlyPlayed().map((t) => t.id), ['x']);
    final look = jsonDecode(b.getMeta('appearance')!) as Map;
    expect(look['accent'], 3); // the backup's setting
    expect(look['textScale'], 0.9); // this screen's own size stays
    expect(tasteB.isDisliked(_t('bad', 'Noise')), isTrue);
    expect(tasteB.artist('Noise'), lessThan(0));

    // Restoring twice changes nothing.
    expect(Backup.restore(b, Backup.decode(file)).changed, 0);
  });

  test('other files are refused', () {
    expect(() => Backup.decode(utf8.encode('{"a":1}')),
        throwsFormatException);
    expect(() => Backup.decode([0xff, 0xfe, 0]), throwsFormatException);
  });
}
