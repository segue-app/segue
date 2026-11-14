import 'dart:math' as math;
import 'dart:typed_data';

/// Where the beats of a stretch of a song are: its tempo, the time of one
/// beat (all others follow every [period]), which beat starts a bar, and
/// how loud it is.
class BeatGrid {
  const BeatGrid({
    required this.bpm,
    required this.firstBeat,
    required this.downbeat,
    required this.confidence,
    required this.energy,
    required this.from,
    required this.to,
  });

  /// Beats per minute (the song's own, at speed 1).
  final double bpm;

  /// Song time of a beat (seconds); the others are [period] apart.
  final double firstBeat;

  /// Which of the four beats after [firstBeat] starts a bar (0..3).
  final int downbeat;

  /// 0..1: how clearly the beat stood out (music ~0.8–0.9, noise ~0.5).
  /// Below 0.6 it's a guess.
  final double confidence;

  /// Loudness of the stretch (dBFS of the RMS).
  final double energy;

  /// The stretch of the song that was analysed (seconds).
  final double from, to;

  double get period => 60 / bpm;

  bool get reliable => confidence >= 0.6;

  /// Phase of song time [t] within the beat: 0 on a beat, up to 1.
  double phaseAt(double t) {
    final x = (t - firstBeat) / period;
    return x - x.floorToDouble();
  }

  /// The first beat that starts a bar at or after song time [t].
  double barAtOrAfter(double t) {
    final first = firstBeat + downbeat * period;
    final bar = period * 4;
    final k = ((t - first) / bar).ceilToDouble();
    return first + k * bar;
  }

  /// The first beat at or after [t].
  double beatAtOrAfter(double t) {
    final k = ((t - firstBeat) / period).ceilToDouble();
    return firstBeat + k * period;
  }

  Map<String, Object> toJson() => {
    'bpm': bpm,
    'b': firstBeat,
    'd': downbeat,
    'c': confidence,
    'e': energy,
    'f': from,
    't': to,
  };

  static BeatGrid? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return BeatGrid(
        bpm: (j['bpm'] as num).toDouble(),
        firstBeat: (j['b'] as num).toDouble(),
        downbeat: (j['d'] as num).toInt(),
        confidence: (j['c'] as num).toDouble(),
        energy: (j['e'] as num).toDouble(),
        from: (j['f'] as num).toDouble(),
        to: (j['t'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'BeatGrid(${bpm.toStringAsFixed(2)} bpm, beat ${firstBeat.toStringAsFixed(3)}s, '
      'bar +$downbeat, conf ${confidence.toStringAsFixed(2)}, '
      '${energy.toStringAsFixed(1)} dB)';
}

/// Finds the beat in mono 16-bit PCM ([sampleRate] Hz) that starts at song
/// time [offset] seconds. Pure Dart, fast enough to run in an isolate on a
/// minute of audio in well under a second.
BeatGrid? analyzeBeats(
  Int16List pcm,
  int sampleRate, {
  double offset = 0,
  double minBpm = 70,
  double maxBpm = 180,
}) {
  const hop = 64;
  final fps = sampleRate / hop;
  final frames = pcm.length ~/ hop;
  if (frames < fps * 8) return null; // under 8 s: not enough to tell

  // Onset strength: spectral flux. Each frame's spectrum (log-compressed)
  // against the one before; only rises count. Kicks, snares, chords and
  // hats all show, whatever the style.
  const n = 512;
  final window = Float64List(n);
  for (var i = 0; i < n; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  final bins = n ~/ 2;
  // Up to ~5 kHz: above it is mostly hiss at this sample rate.
  final topBin = math.min(bins, (5000 / sampleRate * n).round());
  final lowBin = math.max(2, (150 / sampleRate * n).round());
  final re = Float64List(n), im = Float64List(n);
  var prev = Float64List(topBin);
  var cur = Float64List(topBin);
  final onset = Float64List(frames);
  final bassOnset = Float64List(frames);
  final lowLin = Float64List(frames);
  var sumSq = 0.0;
  for (var i = 0; i < pcm.length; i++) {
    final x = pcm[i] / 32768.0;
    sumSq += x * x;
  }
  for (var f = 0; f < frames; f++) {
    final c = f * hop + hop ~/ 2 - n ~/ 2; // frame centred on its hop
    for (var i = 0; i < n; i++) {
      final j = c + i;
      re[i] = j >= 0 && j < pcm.length ? pcm[j] / 32768.0 * window[i] : 0;
      im[i] = 0;
    }
    _fft(re, im);
    var flux = 0.0, bassFlux = 0.0, bass = 0.0;
    for (var b = 1; b < topBin; b++) {
      final m = math.log(1 + 100 * math.sqrt(re[b] * re[b] + im[b] * im[b]));
      cur[b] = m;
      final d = m - prev[b];
      if (d > 0) {
        flux += d;
        if (b <= lowBin) bassFlux += d;
      }
      if (b <= lowBin) bass += re[b] * re[b] + im[b] * im[b];
    }
    onset[f] = f == 0 ? 0 : flux;
    bassOnset[f] = f == 0 ? 0 : bassFlux;
    lowLin[f] = bass;
    final t = prev;
    prev = cur;
    cur = t;
  }
  final rms = math.sqrt(sumSq / pcm.length);
  final energy = 20 * math.log(rms + 1e-9) / math.ln10;

  final win = (fps * 0.5).round();
  void localPeaks(Float64List x) {
    final smooth = Float64List(frames);
    var run = 0.0;
    for (var f = 0; f < frames; f++) {
      run += x[f];
      if (f >= win) run -= x[f - win];
      smooth[f] = run / math.min(f + 1, win);
    }
    var mean = 0.0;
    for (var f = 0; f < frames; f++) {
      x[f] = math.max(0.0, x[f] - smooth[f]);
      mean += x[f];
    }
    mean /= frames;
    if (mean > 0) {
      for (var f = 0; f < frames; f++) {
        x[f] /= mean;
      }
    }
  }

  localPeaks(onset);
  localPeaks(bassOnset);
  // Where the beat falls: the bass (kick) counts as much as everything
  // else together, so the beat lands on the kick, not the hats between.
  final beatOnset = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    beatOnset[f] = onset[f] + bassOnset[f];
  }

  // Tempo: autocorrelation over the lags of minBpm..maxBpm, weighted
  // towards ~120 bpm (a song at 70 or 140 is usually felt at 140 / 70
  // only by machines).
  final minLag = (fps * 60 / maxBpm).floor();
  final maxLag = (fps * 60 / minBpm).ceil();
  final acf = Float64List(4 * maxLag + 2);
  var zero = 0.0;
  for (var f = 0; f < frames; f++) {
    zero += onset[f] * onset[f];
  }
  if (zero <= 0) return null;
  for (var lag = minLag; lag < acf.length; lag++) {
    var s = 0.0;
    for (var f = lag; f < frames; f++) {
      s += onset[f] * onset[f - lag];
    }
    acf[lag] = s / (frames - lag);
  }
  var best = minLag;
  var bestScore = -1.0;
  for (var lag = minLag + 1; lag <= maxLag; lag++) {
    if (acf[lag] < acf[lag - 1] || acf[lag] < acf[lag + 1]) continue;
    final bpm = 60 * fps / lag;
    final octaves = math.log(bpm / 120) / math.ln2;
    final prior = math.exp(-0.5 * octaves * octaves / (1.2 * 1.2));
    // A real beat repeats at two and four beats too (half a bar, a bar);
    // a rhythmic figure (3+3+2 in dancehall) doesn't.
    double at(int l) => l < acf.length ? acf[l] : 0;
    final score = (acf[lag] + 0.8 * at(2 * lag) + 0.6 * at(4 * lag)) * prior;
    if (score > bestScore) {
      bestScore = score;
      best = lag;
    }
  }
  // Parabolic peak for a fractional lag.
  var lag = best.toDouble();
  final y0 = acf[best - 1], y1 = acf[best], y2 = acf[best + 1];
  final den = y0 - 2 * y1 + y2;
  if (den.abs() > 1e-12) lag += 0.5 * (y0 - y2) / den;

  // Period and phase together: a comb of beats over the whole stretch,
  // its period searched finely around the estimate.
  double comb(double period, double phase) {
    var s = 0.0;
    var n = 0;
    for (var t = phase; t < frames - 1; t += period) {
      final i = t.floor();
      final w = t - i;
      s += beatOnset[i] * (1 - w) + beatOnset[i + 1] * w;
      n++;
    }
    return n == 0 ? 0 : s / n;
  }

  var bestPeriod = lag;
  var bestPhase = 0.0;
  var bestComb = -1.0;
  for (var k = -40; k <= 40; k++) {
    final period = lag * (1 + k * 0.0005);
    for (var p = 0.0; p < period; p += 0.5) {
      final c = comb(period, p);
      if (c > bestComb) {
        bestComb = c;
        bestPeriod = period;
        bestPhase = p;
      }
    }
  }
  // Finer phase.
  for (var p = bestPhase - 0.5; p <= bestPhase + 0.5; p += 0.05) {
    if (p < 0) continue;
    final c = comb(bestPeriod, p);
    if (c > bestComb) {
      bestComb = c;
      bestPhase = p;
    }
  }

  // Half way between the beats as strong as on them: those are beats too
  // (the tempo was found at half speed, e.g. 87 for 174).
  var off = comb(bestPeriod, bestPhase + bestPeriod / 2);
  if (off > 0.7 * bestComb && 60 * fps / (bestPeriod / 2) <= maxBpm) {
    bestPeriod /= 2;
    bestPhase = bestPhase % bestPeriod;
    bestComb = -1;
    for (var p = 0.0; p < bestPeriod; p += 0.05) {
      final c = comb(bestPeriod, p);
      if (c > bestComb) {
        bestComb = c;
        bestPhase = p;
      }
    }
    off = comb(bestPeriod, bestPhase + bestPeriod / 2);
  }

  // How much the beat stands out: the comb on the beat against the comb
  // at any other phase (off-beat hats are fine; no beat at all isn't).
  var anyPhase = 0.0;
  var phases = 0;
  for (var p = 0.0; p < bestPeriod; p += bestPeriod / 16, phases++) {
    anyPhase += comb(bestPeriod, p);
  }
  anyPhase /= phases;
  final confidence = bestComb <= 0
      ? 0.0
      : ((bestComb - anyPhase) / bestComb).clamp(0.0, 1.0);

  // The bar: the beat of four with the most bass.
  final bars = Float64List(4);
  var k = 0;
  for (var t = bestPhase; t < frames - 1; t += bestPeriod, k++) {
    // Loudness of the bass just after the beat (not its rise: a soft and
    // a hard kick rise alike on a log scale).
    final i = t.round();
    var e = 0.0;
    for (var j = i; j < math.min(frames, i + (fps * 0.08).round()); j++) {
      e += lowLin[j];
    }
    bars[k % 4] += e;
  }
  var down = 0;
  for (var m = 1; m < 4; m++) {
    if (bars[m] > bars[down]) down = m;
  }

  return BeatGrid(
    bpm: 60 * fps / bestPeriod,
    // The flux rises a little before the hit reaches full strength:
    // ~11 ms, measured on drum loops.
    firstBeat: offset + (bestPhase + 0.5) / fps + 0.011,
    downbeat: down,
    confidence: confidence.toDouble(),
    energy: energy,
    from: offset,
    to: offset + pcm.length / sampleRate,
  );
}

/// In-place radix-2 FFT ([re], [im] of a power-of-two length).
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ar = re[i + k], ai = im[i + k];
        final br = re[i + k + len ~/ 2], bi = im[i + k + len ~/ 2];
        final tr = br * cr - bi * ci;
        final ti = br * ci + bi * cr;
        re[i + k] = ar + tr;
        im[i + k] = ai + ti;
        re[i + k + len ~/ 2] = ar - tr;
        im[i + k + len ~/ 2] = ai - ti;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}
