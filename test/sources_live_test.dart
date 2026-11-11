// Live checks against the real services. They need network access and can
// break when a platform changes its API, which is exactly what they detect.
// Run with: flutter test --tags live
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

Future<void> _check(MusicSource source) async {
  final results = await source.search('daft punk get lucky', limit: 5);
  expect(results, isNotEmpty, reason: '${source.label}: empty search');
  final track = results.first;
  // ignore: avoid_print
  print('${source.label}: "${track.title}" — ${track.artist}');

  final url = (await source.resolveStream(track)).url;
  // Fetch a few bytes to prove the URL actually serves audio.
  final res = await http.get(url, headers: {'Range': 'bytes=0-1023'});
  expect(
    res.statusCode,
    anyOf(200, 206),
    reason: '${source.label}: stream returned ${res.statusCode}',
  );
  // ignore: avoid_print
  print('${source.label}: stream OK (${res.headers['content-type']})');
}

void main() {
  test(
    'YouTube search + stream',
    () => _check(YouTubeSource()),
    timeout: const Timeout(Duration(minutes: 1)),
  );
  test(
    'SoundCloud search + stream',
    () => _check(SoundCloudSource()),
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
