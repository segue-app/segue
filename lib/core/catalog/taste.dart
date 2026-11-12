import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import '../models/track.dart';

/// What you like, learnt from how you listen: songs played to the end
/// count for their artist, songs skipped in the first seconds against it,
/// "Не нравится" a lot. My wave picks artists and orders songs by it, and
/// stops offering what you keep skipping.
class Taste {
  Taste(this.library) {
    _load();
  }

  final LibraryStore library;

  final _artists = <String, double>{};
  final _disliked = <String>{};
  Timer? _save;

  static String norm(String artist) => artist.toLowerCase().trim();

  void _load() {
    try {
      final j = jsonDecode(library.getMeta('taste') ?? '{}') as Map;
      (j['a'] as Map? ?? {}).forEach(
        (k, v) => _artists[k as String] = (v as num).toDouble(),
      );
      _disliked.addAll((j['d'] as List? ?? const []).cast<String>());
    } catch (_) {}
  }

  void _persist() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 3), () {
      // The strongest feelings only: it stays small.
      final top = _artists.entries.toList()
        ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      library.setMeta(
        'taste',
        jsonEncode({
          'a': {for (final e in top.take(600)) e.key: e.value},
          'd': _disliked.toList().reversed.take(1000).toList(),
        }),
      );
    });
  }

  void _add(String artist, double delta) {
    final k = norm(artist);
    if (k.isEmpty) return;
    // Older impressions fade a little with each new one.
    _artists[k] = ((_artists[k] ?? 0) * 0.95 + delta).clamp(-10.0, 10.0);
    _persist();
  }

  /// How a song was left: [played] of [length], [skipped] or ended.
  void record(Track t, Duration played, Duration? length, bool skipped) {
    final fraction = length == null || length.inMilliseconds <= 0
        ? null
        : played.inMilliseconds / length.inMilliseconds;
    double delta;
    if (!skipped) {
      delta = 1; // listened to the end
    } else if (played < const Duration(seconds: 30) &&
        (fraction == null || fraction < 0.3)) {
      delta = -1.2; // skipped right away
    } else if (fraction != null && fraction > 0.7) {
      delta = 0.6; // nearly all of it
    } else {
      return; // half a song says little
    }
    _add(t.artist, delta);
  }

  void liked(Track t) => _add(t.artist, 2);

  /// "Не нравится": the song never comes back in the wave, its artist
  /// much less often.
  void dislike(Track t) {
    _disliked.add(t.key);
    _add(t.artist, -3);
  }

  bool isDisliked(Track t) => _disliked.contains(t.key);

  double artist(String name) => _artists[norm(name)] ?? 0;

  /// Artists you clearly like, best first.
  List<String> favourites({int limit = 12}) {
    final list = _artists.entries.where((e) => e.value >= 1.5).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list.take(limit)) e.key];
  }

  /// Not worth offering in the wave at the moment.
  bool avoid(Track t) => isDisliked(t) || artist(t.artist) <= -4;

  /// [tracks] reordered so liked artists come sooner, with enough chance
  /// in it that the wave doesn't become the same few artists.
  List<Track> order(List<Track> tracks, Random rnd) {
    final keys = {
      for (final t in tracks) t.key: artist(t.artist) * 0.6 + rnd.nextDouble() * 4,
    };
    return [
      for (final t in tracks)
        if (!avoid(t)) t,
    ]..sort((a, b) => keys[b.key]!.compareTo(keys[a.key]!));
  }
}

/// Created in main() and overridden there.
final tasteProvider = Provider<Taste>(
  (ref) => throw UnimplementedError('tasteProvider is overridden in main()'),
);
