import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../downloads/audio_cache.dart';
import '../l10n/l10n.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import 'beat_grid.dart';
import 'beat_service.dart';

/// Leave it playing: it mixes the whole queue by itself, in an order that
/// flows (neighbouring tempos, energy rising to a peak and settling), and
/// fetches the songs ahead so a dropped connection doesn't stop the music.
class AutoDj {
  AutoDj({required this.player, required this.beats, required this.cache});

  final SegueAudioHandler player;
  final BeatService beats;
  final AudioCache cache;

  /// How many songs ahead are kept on the device.
  static const ahead = 15;

  final on = ValueNotifier(false);

  /// What it's doing, for the screen ("Анализирую 4 из 20").
  final status = ValueNotifier<String?>(null);

  VoidCallback? _queueListener;
  bool _fetching = false;

  void setOn(bool v) {
    if (on.value == v) return;
    on.value = v;
    if (v) {
      _queueListener = _fetchAhead;
      player.queueVersion.addListener(_queueListener!);
      _fetchAhead();
    } else {
      if (_queueListener != null) {
        player.queueVersion.removeListener(_queueListener!);
      }
      _queueListener = null;
      status.value = null;
    }
  }

  /// Keeps the next [ahead] songs on the device, one at a time.
  Future<void> _fetchAhead() async {
    if (_fetching || !on.value) return;
    _fetching = true;
    try {
      while (on.value) {
        final upcoming = player.tracks
            .skip(player.index + 1)
            .take(ahead)
            .where((t) => t.source != SourceKind.local)
            .toList();
        final missing = upcoming.where((t) => !cache.contains(t)).toList();
        if (missing.isEmpty) {
          if (status.value?.startsWith('Скачиваю'.tr) ?? false) {
            status.value = 'Следующие {0} треков на устройстве'.trArgs([
              upcoming.length,
            ]);
          }
          break;
        }
        status.value = 'Скачиваю сет: {0} из {1}'.trArgs([
          upcoming.length - missing.length + 1,
          upcoming.length,
        ]);
        await cache.keep(missing.first, always: true);
        // Not kept (offline, no Wi-Fi on a phone): try again later.
        if (!cache.contains(missing.first)) break;
      }
    } finally {
      _fetching = false;
    }
  }

  /// Puts the songs after the current one in an order that flows.
  Future<void> arrange() async {
    final upcoming = player.tracks.skip(player.index + 1).take(60).toList();
    if (upcoming.length < 3) return;
    final grids = <Track, BeatGrid?>{};
    for (var i = 0; i < upcoming.length; i++) {
      status.value = 'Анализирую {0} из {1}'.trArgs([i + 1, upcoming.length]);
      final t = upcoming[i];
      grids[t] = await beats
          .intro(t, await player.startOf(t))
          .timeout(const Duration(seconds: 30), onTimeout: () => null)
          .catchError((Object _) => null);
    }
    final cur = player.current;
    final start = cur == null ? null : player.dj.outgoingGrid;
    final ordered = orderSet(upcoming, grids, start: start);
    // The queue may have moved on meanwhile: only the same songs.
    final now = player.tracks.skip(player.index + 1).take(60).toList();
    if (now.length == upcoming.length &&
        now.every((t) => upcoming.any((u) => u.key == t.key))) {
      player.setUpcoming([
        ...ordered,
        ...player.tracks.skip(player.index + 1 + upcoming.length),
      ]);
    }
    status.value = 'Сет выстроен'.tr;
    unawaited(_fetchAhead());
  }

  /// The order: each next song close in tempo to the one before, energy
  /// climbing to a peak about two thirds in, then easing. Songs without a
  /// known beat go to the end, as they were.
  @visibleForTesting
  static List<Track> orderSet(
    List<Track> tracks,
    Map<Track, BeatGrid?> grids, {
    BeatGrid? start,
  }) {
    final known = [
      for (final t in tracks)
        if (grids[t]?.reliable ?? false) t,
    ];
    final unknown = [
      for (final t in tracks)
        if (!(grids[t]?.reliable ?? false)) t,
    ];
    if (known.isEmpty) return tracks;
    final energies = [for (final t in known) grids[t]!.energy];
    final lo = energies.reduce(math.min), hi = energies.reduce(math.max);
    final out = <Track>[];
    final left = [...known];
    var bpm = start?.bpm ?? grids[known.first]!.bpm;
    while (left.isNotEmpty) {
      final i = out.length / math.max(1, known.length - 1);
      // Wanted energy: up to the peak at ~70 %, then down a little.
      final want = i < 0.7
          ? lo + (hi - lo) * (i / 0.7)
          : hi - (hi - lo) * 0.5 * ((i - 0.7) / 0.3);
      Track? best;
      var bestCost = double.infinity;
      for (final t in left) {
        final g = grids[t]!;
        final tempo = (_octaves(g.bpm / bpm)).abs() * 12; // ~semitones
        final energy = hi > lo ? (g.energy - want).abs() / (hi - lo) * 3 : 0;
        final cost = tempo + energy;
        if (cost < bestCost) {
          bestCost = cost;
          best = t;
        }
      }
      out.add(best!);
      left.remove(best);
      bpm = grids[best]!.bpm;
    }
    return [...out, ...unknown];
  }

  /// Tempo distance in octaves, half and double counting as the same.
  static double _octaves(double ratio) {
    var o = math.log(ratio) / math.ln2;
    while (o > 0.5) {
      o -= 1;
    }
    while (o < -0.5) {
      o += 1;
    }
    return o;
  }
}

/// Set in main(); null where there's no player (tests, tools).
final autoDjProvider = Provider<AutoDj?>((ref) => null);
