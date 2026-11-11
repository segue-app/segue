import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/lyrics/lyrics.dart';
import 'package:segue/core/models/track.dart';

void main() {
  test('parses LRC, sorts, handles several stamps per line', () {
    final l = Lyrics.parseLrc('''
[ar:Someone]
[00:08.01] First line
[00:14.50]Second
[00:20.00][01:00.00] Chorus
''');
    expect(l.lines.map((e) => e.text), [
      'First line',
      'Second',
      'Chorus',
      'Chorus',
    ]);
    expect(l.lines[1].time, const Duration(milliseconds: 14500));
    expect(l.lines.last.time, const Duration(minutes: 1));
  });

  test('lineAt finds the current line', () {
    final l = Lyrics.parseLrc('[00:05.00]a\n[00:10.00]b\n[00:15.00]c');
    expect(l.lineAt(const Duration(seconds: 2)), -1);
    expect(l.lineAt(const Duration(seconds: 5)), 0);
    expect(l.lineAt(const Duration(seconds: 12)), 1);
    expect(l.lineAt(const Duration(minutes: 3)), 2);
  });

  test('cleanQuery strips video noise and keeps the artist', () {
    Track t(String title, String artist) => Track(
      id: 'x',
      source: SourceKind.youtube,
      title: title,
      artist: artist,
    );
    expect(
      LyricsService.cleanQuery(
        t('Dua Lipa - Training Season (Official Music Video)', 'Dua Lipa'),
      ),
      'Dua Lipa - Training Season',
    );
    expect(LyricsService.cleanQuery(t('Фея [4K]', 'Miyagi')), 'Miyagi Фея');
    expect(
      LyricsService.cleanQuery(
        t('Blinding Lights ft. Someone | Lyrics', 'The Weeknd'),
      ),
      'The Weeknd Blinding Lights',
    );
  });

  test('estimated word timing spreads the line by word length', () {
    final l = Lyrics.parseLrc('[00:10.00]Hi there friend\n[00:20.00]next');
    final w = l.wordsOf(0);
    expect(w.map((e) => e.text), ['Hi', 'there', 'friend']);
    expect(w.first.start, const Duration(seconds: 10));
    // Contiguous, longer words take longer.
    expect(w[1].start, w[0].end);
    expect(w[2].end - w[2].start > w[0].end - w[0].start, isTrue);
    // Capped by singing pace, not stretched to the next line.
    expect(w.last.end < const Duration(seconds: 20), isTrue);
    expect(w[0].progressAt(const Duration(seconds: 9)), 0);
    expect(w.last.progressAt(const Duration(seconds: 19)), 1);
  });

  test('enhanced LRC word stamps are used as-is', () {
    final l = Lyrics.parseLrc(
      '[00:01.00]<00:01.00>One <00:01.50>two <00:02.40>three',
    );
    expect(l.lines.single.text, 'One two three');
    final w = l.wordsOf(0);
    expect(w.map((e) => e.text), ['One', 'two', 'three']);
    expect(w[1].start, const Duration(milliseconds: 1500));
    expect(w[1].end, const Duration(milliseconds: 2400));
  });
}
