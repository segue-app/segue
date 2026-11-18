// ignore_for_file: avoid_print
// Finds real songs on SoundCloud as YouTube stand-ins (network required).
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/stand_in.dart';

void main() {
  test('stand-ins for well-known songs', () async {
    final s = StandIn([SoundCloudSource()]);
    var hits = 0;
    for (final (title, artist, secs) in [
      ('Blinding Lights', 'The Weeknd', 200),
      ('Shape of You', 'Ed Sheeran', 233),
      ('Кукла колдуна', 'Король и Шут', 205),
      ('Smells Like Teen Spirit', 'Nirvana', 301),
      ('Розовое вино', 'Элджей', 190),
    ]) {
      final t = await s.find(
        Track(
          id: title,
          source: SourceKind.match,
          title: title,
          artist: artist,
          duration: Duration(seconds: secs),
        ),
      );
      print(
        '$artist — $title → ${t == null ? 'none' : '${t.artist} — ${t.title} (${t.duration?.inSeconds}s)'}',
      );
      if (t != null) hits++;
    }
    expect(hits, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
