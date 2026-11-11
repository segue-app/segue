import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/match_source.dart';

Track _yt(String title, String artist, int sec) => Track(
  id: title,
  source: SourceKind.youtube,
  title: title,
  artist: artist,
  duration: Duration(seconds: sec),
);

void main() {
  final wanted = Track(
    id: 'x',
    source: SourceKind.match,
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    duration: const Duration(seconds: 200),
  );

  test('prefers same length and avoids live/remix/sped-up versions', () {
    final best = MatchSource.pickBest(wanted, [
      _yt('The Weeknd - Blinding Lights (Live at the Grammys)', 'Grammys', 205),
      _yt('Blinding Lights sped up', 'Someone', 160),
      _yt('The Weeknd - Blinding Lights (Official Audio)', 'The Weeknd', 201),
      _yt('Blinding Lights Remix', 'DJ X', 199),
    ]);
    expect(best.title, 'The Weeknd - Blinding Lights (Official Audio)');
  });

  test('keeps a variant when the original asks for it', () {
    final remix = Track(
      id: 'y',
      source: SourceKind.match,
      title: 'Blinding Lights (Remix)',
      artist: 'The Weeknd',
      duration: const Duration(seconds: 220),
    );
    final best = MatchSource.pickBest(remix, [
      _yt('The Weeknd - Blinding Lights', 'The Weeknd', 200),
      _yt('The Weeknd - Blinding Lights (Remix)', 'The Weeknd', 221),
    ]);
    expect(best.title, contains('Remix'));
  });
}
