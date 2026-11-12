@Tags(['live'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/match_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

/// Real songs as an import would bring them (Deezer metadata), matched on
/// YouTube. Prints what was picked; run by hand: flutter test test/live.
const _queries = [
  'Кино Группа крови',
  'Баста Сансара',
  'Miyagi Andy Panda Kosandra',
  'Zivert Life',
  'Queen Bohemian Rhapsody',
  'The Weeknd Blinding Lights',
  'Скриптонит Космос',
  'Макс Корж Мотылёк',
  'Rammstein Sonne',
  'Imagine Dragons Believer',
  'Ленинград Экспонат',
  'Мот Капкан',
  'Би-2 Полковнику никто не пишет',
  'Arctic Monkeys Do I Wanna Know',
  'Король и Шут Лесник',
  'Jah Khalib Леди',
  'HammAli Navai Птичка',
  'Eminem Lose Yourself',
  'Земфира Хочешь',
  'Instasamka За деньги да',
];

void main() {
  test('match probe', () async {
    final yt = YouTubeSource();
    final match = MatchSource(yt);
    for (final q in _queries) {
      // ignore: avoid_print
      final res = await http.get(
        Uri.parse('https://api.deezer.com/search?q=${Uri.encodeQueryComponent(q)}&limit=1'),
      );
      final d = ((jsonDecode(res.body) as Map)['data'] as List).first as Map;
      final wanted = Track(
        id: 'p${d['id']}',
        source: SourceKind.match,
        title: d['title'] as String,
        artist: (d['artist'] as Map)['name'] as String,
        duration: Duration(seconds: d['duration'] as int),
      );
      // ignore: avoid_print
      final sw = Stopwatch()..start();
      final Track got;
      try {
        got = await match.findMatch(wanted);
      } catch (e) {
        // ignore: avoid_print
        print('${wanted.artist} — ${wanted.title}: $e');
        continue;
      }
      // ignore: avoid_print
      print('${wanted.artist} — ${wanted.title} (${wanted.duration!.inSeconds}s)\n'
          '   → ${got.artist} — ${got.title} (${got.duration?.inSeconds}s) '
          '${sw.elapsedMilliseconds}ms');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
