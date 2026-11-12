import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/lyrics/lyrics.dart';

void main() {
  test('NetEase word timing: words, lines, no credits', () {
    const yrc =
        '{"t":0,"c":[{"tx":"作词: "},{"tx":"Someone"}]}\n'
        '[1000,2000](1000,500,0)Hello (1500,700,0)(yeah) (2200,800,0)world\n'
        '[4000,1500](4000,1500,0)Again\n'
        '[6000,500](6000,500,0)作词 : Somebody\n';
    final l = Lyrics.parseYrc(yrc);
    expect(l.lines.map((x) => x.text), ['Hello (yeah) world', 'Again']);
    expect(l.wordSynced, isTrue);
    final w = l.lines.first.words!;
    expect(w.map((x) => x.text), ['Hello', '(yeah)', 'world']);
    expect(w[1].start, const Duration(milliseconds: 1500));
    expect(w[1].end, const Duration(milliseconds: 2200));
  });

  test('a found song must be the same song', () {
    const want = (artist: 'МОТ', title: 'Капкан');
    const d = Duration(seconds: 228);
    expect(LyricsService.similarity(want, d, 'Капкан', 'Mot', d), greaterThan(0));
    expect(LyricsService.similarity(want, d, 'Другая песня', 'МОТ', d), 0);
    expect(LyricsService.similarity(want, d, 'Капкан', 'Someone Else', d), 0);
  });
}
