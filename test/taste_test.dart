import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/catalog/taste.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id, String artist) =>
    Track(id: id, source: SourceKind.youtube, title: 'Song $id', artist: artist);

void main() {
  test('skips push an artist out, full listens pull it in', () {
    final taste = Taste(LibraryStore.memory());
    const len = Duration(minutes: 3);
    for (var i = 0; i < 4; i++) {
      taste.record(_t('s$i', 'Skipped'), const Duration(seconds: 5), len, true);
      taste.record(_t('l$i', 'Loved'), len, len, false);
    }
    expect(taste.artist('Skipped'), lessThan(-4));
    expect(taste.artist('loved'), greaterThan(3)); // case-insensitive
    expect(taste.favourites(), ['loved']);
    // Half-listened skips say nothing.
    taste.record(_t('m', 'Middle'), const Duration(seconds: 80), len, true);
    expect(taste.artist('Middle'), 0);

    final ordered = taste.order([
      _t('a', 'Skipped'),
      _t('b', 'Other'),
      _t('c', 'Loved'),
    ], Random(1));
    expect(ordered.map((t) => t.id), isNot(contains('a')));
    expect(ordered.first.id, 'c');
  });

  test('dislike removes the song for good and remembers it', () {
    final lib = LibraryStore.memory();
    final taste = Taste(lib);
    final song = _t('x', 'Artist');
    taste.dislike(song);
    expect(taste.avoid(song), isTrue);
    expect(taste.avoid(_t('y', 'Artist')), isFalse); // -3 is not out yet
  });
}
