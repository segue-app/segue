import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/dj/beat_grid.dart';

/// A drum loop: a kick on every beat (stronger on the first of four), a
/// hat between, some noise. [start] is where the first kick falls.
Int16List _loop(double bpm, double seconds, double start, {int sr = 11025}) {
  final n = (seconds * sr).round();
  final out = Float64List(n);
  final rnd = math.Random(7);
  final period = 60 / bpm;
  var beat = 0;
  for (var t = start; t < seconds; t += period, beat++) {
    final i0 = (t * sr).round();
    final strong = beat % 4 == 0 ? 1.0 : 0.6;
    for (var i = 0; i < sr * 0.12 && i0 + i < n; i++) {
      final x = i / sr;
      out[i0 + i] += strong * math.sin(2 * math.pi * 60 * x) * math.exp(-x * 30);
    }
    final h0 = ((t + period / 2) * sr).round();
    for (var i = 0; i < sr * 0.03 && h0 + i < n; i++) {
      out[h0 + i] += 0.15 * (rnd.nextDouble() * 2 - 1) * math.exp(-i / sr * 120);
    }
  }
  return Int16List.fromList([
    for (var i = 0; i < n; i++)
      ((out[i] * 0.6 + (rnd.nextDouble() - 0.5) * 0.02) * 32767)
          .round()
          .clamp(-32768, 32767),
  ]);
}

void main() {
  for (final (bpm, start) in [(128.0, 0.37), (96.0, 1.1), (174.0, 0.2), (89.0, 0.05)]) {
    test('finds $bpm bpm and where the beats fall', () {
      final g = analyzeBeats(_loop(bpm, 40, start), 11025, offset: 100)!;
      expect(g.bpm, closeTo(bpm, 0.15), reason: '$g');
      // The beat at song time 100 + start (any whole beat away).
      final d = g.phaseAt(100 + start);
      final signed = (d > 0.5 ? d - 1 : d) * g.period; // + = found early
      final err = signed.abs();
      expect(err, lessThan(0.015), reason: '$g, off by ${err * 1000} ms');
      // Bars start on the strong kick.
      final bar = g.barAtOrAfter(100 + start);
      final beats = ((bar - 100 - start) / g.period).round();
      expect(beats % 4, 0, reason: '$g');
      expect(g.reliable, isTrue);
    });
  }

  test('noise has no confident beat', () {
    final rnd = math.Random(1);
    final noise = Int16List.fromList([
      for (var i = 0; i < 11025 * 20; i++) (rnd.nextDouble() * 2000 - 1000).round(),
    ]);
    final g = analyzeBeats(noise, 11025);
    expect(g == null || !g.reliable, isTrue, reason: '$g');
  });
}
