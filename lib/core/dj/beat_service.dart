import 'dart:math' as math;
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'beat_grid.dart';
import 'pcm_decoder.dart';

/// Beat grids of songs, where a mix needs them: the end of the song that
/// plays (where it's mixed out) and the start of the next (where it comes
/// in). Analysed in the background as a song starts, kept for next time.
class BeatService {
  BeatService({
    required this.uriFor,
    this.load,
    this.save,
    this.get,
    this.put,
    PcmDecoder? decoder,
  }) : _decoder = decoder ?? PcmDecoder();

  /// A URL libmpv can open for the song.
  final Future<Uri> Function(Track track) uriFor;

  /// Stored grids (from an earlier session), and where to keep new ones.
  final Map<String, dynamic>? Function()? load;
  final void Function(Map<String, dynamic> all)? save;

  /// One grid at a time from storage (instead of [load]/[save] of all).
  final Object? Function(String key)? get;
  final void Function(String key, Object json)? put;

  final PcmDecoder _decoder;
  final _cache = <String, Future<BeatGrid?>>{};
  Map<String, dynamic>? _stored;
  Timer? _saveTimer;

  /// How much of a song is analysed at each end (seconds).
  static const span = 30.0;

  static String _key(Track t, String end, double at) =>
      '${t.key}|$end|${at.round()}';

  /// The grid of the [span] seconds before [end] (the mix out).
  Future<BeatGrid?> outro(Track t, Duration end) {
    final to = end.inMilliseconds / 1000;
    final from = (to - span).clamp(0.0, double.infinity);
    return _grid(t, 'o', from, to - from);
  }

  /// The grid of the [span] seconds from [start] (the mix in).
  Future<BeatGrid?> intro(Track t, Duration start) =>
      _grid(t, 'i', start.inMilliseconds / 1000, span);

  /// The grid of [span] seconds from [at] in the middle of a song (for
  /// lights, when the start has no clear beat).
  Future<BeatGrid?> middle(Track t, Duration at) =>
      _grid(t, 'm', at.inMilliseconds / 1000, span);

  /// Already known, without waiting.
  BeatGrid? knownIntro(Track t, Duration start) =>
      _known(_key(t, 'i', start.inMilliseconds / 1000));

  BeatGrid? knownOutro(Track t, Duration end) =>
      _known(_key(t, 'o', end.inMilliseconds / 1000));

  BeatGrid? _known(String key) {
    final one = get;
    if (one != null) {
      return _stored?[key] != null
          ? BeatGrid.fromJson(_stored![key])
          : BeatGrid.fromJson(one(key));
    }
    return BeatGrid.fromJson(_storedMap()[key]);
  }

  Map<String, dynamic> _storedMap() => _stored ??= {...?load?.call()};

  Future<BeatGrid?> _grid(Track t, String end, double from, double length) {
    final key = _key(t, end, end == 'o' ? from + length : from);
    final known = _known(key);
    if (known != null) return Future.value(known);
    return _cache[key] ??= () async {
      try {
        final uri = await uriFor(t);
        final pcm = await _decoder.decode(
          uri,
          start: Duration(milliseconds: (from * 1000).round()),
          length: Duration(milliseconds: (length * 1000).round()),
        );
        if (pcm == null || pcm.length < PcmDecoder.sampleRate * 8) {
          _log('beats ${t.title} $end: no audio (${pcm?.length})');
          return null;
        }
        final grid = await _analyse(pcm, from);
        if (grid != null) _remember(key, grid);
        _log('beats ${t.title} $end@${from.toStringAsFixed(0)}s: $grid');
        return grid;
      } catch (e) {
        _log('beats ${t.title}: $e');
        _cache.remove(key); // try again another time
        return null;
      }
    }();
  }

  final _loud = <String, Future<double?>>{};

  /// How loud a song is, in YouTube's terms (dB over its reference, about
  /// −14 LUFS), measured on the whole song: for sources that don't say it
  /// themselves.
  Future<double?> loudness(Track t, Duration? length) =>
      _loud[t.key] ??= () async {
        try {
          // The whole song: a chorus alone reads several dB louder.
          final pcm = await _decoder.decode(
            await uriFor(t),
            length: length == null || length > const Duration(minutes: 12)
                ? const Duration(minutes: 12)
                : null,
          );
          if (pcm == null || pcm.length < PcmDecoder.sampleRate * 5) {
            _loud.remove(t.key);
            return null;
          }
          final db = loudnessOf(pcm);
          _log('loudness ${t.title}: ${db?.toStringAsFixed(1)} dB');
          return db;
        } catch (e) {
          _loud.remove(t.key);
          return null;
        }
      }();

  /// Loudness of mono samples by BS.1770 (K filter, 400 ms blocks, both
  /// gates), on YouTube's scale.
  @visibleForTesting
  static double? loudnessOf(Int16List pcm) {
    const rate = PcmDecoder.sampleRate;
    final x = _kWeighted(pcm, rate.toDouble());
    const block = rate * 4 ~/ 10, hop = rate ~/ 10;
    final powers = <double>[];
    for (var i = 0; i + block <= x.length; i += hop) {
      var sum = 0.0;
      for (var j = i; j < i + block; j++) {
        sum += x[j] * x[j];
      }
      powers.add(sum / block);
    }
    double lufs(double p) => 10 * math.log(p) / math.ln10 - 0.691;
    var kept = [
      for (final p in powers)
        if (p > 0 && lufs(p) > -70) p,
    ];
    if (kept.isEmpty) return null;
    final mean = kept.reduce((a, b) => a + b) / kept.length;
    kept = [
      for (final p in kept)
        if (lufs(p) > lufs(mean) - 10) p,
    ];
    final gated = kept.reduce((a, b) => a + b) / kept.length;
    // A mono mix of stereo carries half the power BS.1770 sums over both
    // channels: +3 dB. [loudnessOffset] is what is left against YouTube.
    return lufs(gated) + 3 + loudnessOffset + 14;
  }

  /// Fitted on songs whose loudness YouTube reports.
  static const loudnessOffset = -2.4;

  /// The K filter (a high shelf, then a high pass), for any sample rate
  /// (coefficients as libebur128 derives them).
  static Float64List _kWeighted(Int16List pcm, double fs) {
    var f0 = 1681.974450955533, q = 0.7071752369554196;
    const g = 3.999843853973347;
    var k = math.tan(math.pi * f0 / fs);
    final vh = math.pow(10, g / 20).toDouble();
    final vb = math.pow(vh, 0.4996667741545416).toDouble();
    var a0 = 1 + k / q + k * k;
    final b = [
      (vh + vb * k / q + k * k) / a0,
      2 * (k * k - vh) / a0,
      (vh - vb * k / q + k * k) / a0,
    ];
    final a = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0];
    f0 = 38.13547087602444;
    q = 0.5003270373238773;
    k = math.tan(math.pi * f0 / fs);
    a0 = 1 + k / q + k * k;
    final ra = [2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0];
    final out = Float64List(pcm.length);
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0; // shelf
    var u1 = 0.0, u2 = 0.0, z1 = 0.0, z2 = 0.0; // high pass
    for (var i = 0; i < pcm.length; i++) {
      final x0 = pcm[i] / 32768;
      final y0 = b[0] * x0 + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
      x2 = x1;
      x1 = x0;
      y2 = y1;
      y1 = y0;
      final z0 = y0 - 2 * u1 + u2 - ra[0] * z1 - ra[1] * z2;
      u2 = u1;
      u1 = y0;
      z2 = z1;
      z1 = z0;
      out[i] = z0;
    }
    return out;
  }

  void _remember(String key, BeatGrid g) {
    final one = put;
    if (one != null) {
      one(key, g.toJson());
      return;
    }
    final all = _storedMap();
    all[key] = g.toJson();
    while (all.length > 4000) {
      all.remove(all.keys.first);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () => save?.call(all));
  }

  Future<void> dispose() => _decoder.dispose();

  /// In a background isolate. Static, so the closure carries only the
  /// samples (an instance method's would drag the whole service along).
  static Future<BeatGrid?> _analyse(Int16List pcm, double from) =>
      Isolate.run(() => analyzeBeats(pcm, PcmDecoder.sampleRate, offset: from));

  static void _log(String m) => debugPrint(m);
}
