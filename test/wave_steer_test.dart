import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/catalog/deezer.dart';
import 'package:segue/core/catalog/taste.dart';
import 'package:segue/core/catalog/wave.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/youtube_source.dart';

Track yt(String id, String title, [String channel = 'Lyrics Channel']) =>
    Track(
      id: id,
      source: SourceKind.youtube,
      title: title,
      artist: channel,
      duration: const Duration(minutes: 3),
    );

/// Mixes without the network: each seed gives songs of six artists.
class _FakeYouTube extends YouTubeSource {
  int calls = 0;
  @override
  Future<List<Track>> mix(String videoId) async {
    calls++;
    return [
      for (var a = 0; a < 6; a++)
        for (var s = 0; s < 4; s++)
          yt('$videoId-$a-$s', 'Artist $a$videoId - Song $s (Official Video)'),
      yt('$videoId-long', 'Artist X - Best songs 1 hour'),
      // The same song from another channel.
      yt('$videoId-copy', 'Artist 0$videoId - Song 0 [Lyrics]'),
    ];
  }
}

void main() {
  test('steered wave: mixes of your songs, spaced, nothing twice', () async {
    final library = LibraryStore.memory();
    for (final id in ['a', 'b', 'c']) {
      library.setLiked(yt(id, 'Mine $id', 'Me $id'), true);
    }
    final taste = Taste(library);
    for (var i = 0; i < 5; i++) {
      taste.dislike(yt('x', 'x', 'Artist 1a'));
    }
    final youtube = _FakeYouTube();
    final wave = Wave(Catalog(), library, null, taste: taste, youtube: youtube);
    final all = <Track>[];
    for (var i = 0; i < 6; i++) {
      all.addAll(await wave.steeredBatch());
    }
    expect(all, isNotEmpty);
    expect(all.map((t) => t.key).toSet().length, all.length);
    expect(all.where((t) => t.title.contains('1 hour')), isEmpty);
    expect(all.where((t) => t.title.startsWith('Artist 1a ')), isEmpty);
    // One upload of a song only.
    final names = all
        .map((t) => t.title.replaceAll(RegExp(r'\s*[(\[].*'), ''))
        .toList();
    expect(names.toSet().length, names.length);
    // No artist twice within four songs.
    for (var i = 1; i < all.length; i++) {
      for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
        String who(Track t) => t.title.split(' - ').first;
        expect(who(all[i]), isNot(who(all[j])));
      }
    }
    expect(youtube.calls, greaterThan(0));
  });
}
