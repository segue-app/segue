@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/lyrics/lyrics.dart';
import 'package:segue/core/models/track.dart';

Track _m(String artist, String title, int secs, {SourceKind s = SourceKind.match}) =>
    Track(
      id: '$artist$title',
      source: s,
      title: title,
      artist: artist,
      duration: Duration(seconds: secs),
    );

void main() {
  test('lyrics probe', () async {
    final svc = LyricsService();
    final cases = [
      _m('МОТ', 'Капкан', 228),
      _m('The Weeknd', 'Blinding Lights', 200),
      _m('Miyagi & Andy Panda', 'Kosandra', 221),
      _m('Zivert', 'Life', 188),
      _m('Кино', 'Группа крови', 284),
      _m('Скриптонит', 'Космос (feat. Charusha)', 227),
      _m('Queen', 'Bohemian Rhapsody - Remastered 2011', 354),
      _m('Imagine Dragons', 'Believer', 202),
      _m('МОТ', 'Мот - Капкан (премьера клипа, 2016)', 234, s: SourceKind.youtube),
      _m('Nobody Real', 'Zzqx Unknown Song Title', 200),
    ];
    for (final t in cases) {
      final sw = Stopwatch()..start();
      final l = await svc.fetch(t);
      final first = l == null || l.lines.isEmpty
          ? ''
          : l.lines.firstWhere((x) => x.text.isNotEmpty, orElse: () => l.lines.first).text;
      // ignore: avoid_print
      print('${t.artist} — ${t.title}: '
          '${l == null ? 'none' : '${l.source} ${l.wordSynced ? 'WORDS' : (l.synced ? 'lines' : 'plain')} ${l.lines.length} lines, len ${l.length?.inSeconds}s'} '
          '${sw.elapsedMilliseconds}ms | $first');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
