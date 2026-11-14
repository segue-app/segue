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
  BeatService({required this.uriFor, this.load, this.save, PcmDecoder? decoder})
    : _decoder = decoder ?? PcmDecoder();

  /// A URL libmpv can open for the song.
  final Future<Uri> Function(Track track) uriFor;

  /// Stored grids (from an earlier session), and where to keep new ones.
  final Map<String, dynamic>? Function()? load;
  final void Function(Map<String, dynamic> all)? save;

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

  BeatGrid? _known(String key) => BeatGrid.fromJson(_storedMap()[key]);

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

  void _remember(String key, BeatGrid g) {
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
