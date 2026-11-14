import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/dj/auto_dj.dart';
import 'package:segue/core/dj/beat_grid.dart';
import 'package:segue/core/models/track.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: id, artist: 'A');

BeatGrid _g(double bpm, double db, {double conf = 0.9}) => BeatGrid(
  bpm: bpm,
  firstBeat: 0,
  downbeat: 0,
  confidence: conf,
  energy: db,
  from: 0,
  to: 30,
);

void main() {
  test('a set flows: neighbouring tempos, energy up then down', () {
    final songs = {
      _t('a'): _g(124, -12),
      _t('b'): _g(90, -14),
      _t('c'): _g(126, -8),
      _t('d'): _g(92, -10),
      _t('e'): _g(125, -10),
      _t('x'): _g(110, -9, conf: 0.3), // no clear beat
    };
    final order = AutoDj.orderSet(
      songs.keys.toList(),
      songs,
      start: _g(123, -12),
    );
    final ids = order.map((t) => t.id).toList();
    // Starts near the current 123 bpm; the 90s come together; the
    // unclear one last.
    expect(['a', 'e', 'c'].contains(ids.first), isTrue, reason: '$ids');
    final bd = [ids.indexOf('b'), ids.indexOf('d')]..sort();
    expect(bd[1] - bd[0], 1, reason: '$ids');
    expect(ids.last, 'x');
    expect(ids.toSet().length, 6);
  });

  test('half and double tempo count as close', () {
    final songs = {_t('fast'): _g(172, -9), _t('mid'): _g(110, -9)};
    final order = AutoDj.orderSet(songs.keys.toList(), songs, start: _g(86, -9));
    expect(order.first.id, 'fast');
  });
}
