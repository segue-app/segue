// Live checks against real services (network). Run: flutter test --tags live
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/import/playlist_importer.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/match_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  final importer = PlaylistImporter()
    ..soundcloudClientId = SoundCloudSource().clientId;

  test('Spotify playlist via embed', () async {
    final p = await importer.import(
      'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=x',
    );
    // ignore: avoid_print
    print(
      'Spotify: ${p.name}, ${p.tracks.length} tracks, first: ${p.tracks.first.artist} — ${p.tracks.first.title}',
    );
    expect(p.tracks.length, greaterThan(10));
    expect(p.tracks.first.source, SourceKind.match);
    expect(p.tracks.first.duration, isNotNull);
  });

  test('Yandex Music playlist via public API', () async {
    final p = await importer.import(
      'https://music.yandex.ru/users/yamusic-top/playlists/1076',
    );
    // ignore: avoid_print
    print(
      'Yandex: ${p.name}, ${p.tracks.length} tracks, first: ${p.tracks.first.artist} — ${p.tracks.first.title}',
    );
    expect(p.tracks.length, greaterThan(10));
    expect(p.tracks.first.artworkUrl, startsWith('https://'));
  });

  test('imported track is matched and playable on YouTube', () async {
    final p = await importer.import(
      'https://music.yandex.ru/users/yamusic-top/playlists/1076',
    );
    final yt = YouTubeSource();
    final match = MatchSource(yt);
    final t = p.tracks.first;
    final found = await match.findMatch(t);
    // ignore: avoid_print
    print(
      'Match: "${t.artist} — ${t.title}" (${t.duration?.inSeconds}s) → "${found.title}" by ${found.artist} (${found.duration?.inSeconds}s)',
    );
    final stream = await match.resolveStream(t);
    expect(stream.url.host, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('unsupported links explain what works', () {
    expect(
      () => importer.import('https://example.com/x'),
      throwsA(isA<ImportException>()),
    );
  });
}
