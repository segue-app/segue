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

  test('Apple Music playlist and album from the web page', () async {
    final p = await importer.import(
      'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb',
    );
    expect(p.name, isNot(contains('Apple Music')));
    expect(p.tracks.length, greaterThan(10));
    expect(p.tracks.first.artist, isNotEmpty);
    expect(p.tracks.first.artworkUrl, startsWith('https://'));
    final a = await importer.import(
      'https://music.apple.com/ru/album/abbey-road-remastered/1441164426',
    );
    expect(a.tracks.first.title, 'Come Together');
    expect(a.tracks.first.artist, 'The Beatles');
  });

  test('Deezer playlist and album via the open API', () async {
    final p = await importer.import(
      'https://www.deezer.com/en/playlist/908622995',
    );
    expect(p.tracks.length, greaterThan(10));
    expect(p.tracks.first.source, SourceKind.match);
    expect(p.tracks.first.duration, isNotNull);
    final a = await importer.import('https://www.deezer.com/album/302127');
    expect(a.tracks, isNotEmpty);
    expect(a.tracks.first.artworkUrl, isNotNull);
  });
}
