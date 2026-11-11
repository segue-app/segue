import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player.dart';
import '../../core/settings/settings.dart';
import '../widgets/artwork.dart';
import 'theme.dart';

/// Colours picked from a cover image, used to tint the player.
class ArtworkColors {
  const ArtworkColors({
    required this.accent,
    required this.background,
    required this.palette,
  });

  /// Bright tone for the progress bar and play button.
  final Color accent;

  /// Deep tone for the backdrop behind the player.
  final Color background;

  /// The cover's main colours (4), most prominent first. Drives the
  /// animated backdrop.
  final List<Color> palette;

  static const fallback = ArtworkColors(
    accent: SegueColors.accent,
    background: Color(0xFF1E1716),
    palette: [
      Color(0xFF8A3B2E),
      Color(0xFF5B2A4A),
      Color(0xFF2E3A6B),
      Color(0xFF9A6A3A),
    ],
  );
}

final _colorsForUrl = FutureProvider.family<ArtworkColors, String>((
  ref,
  url,
) async {
  try {
    final provider = ResizeImage(coverProvider(url), width: 48, height: 48);
    final scheme = await ColorScheme.fromImageProvider(
      provider: provider,
      brightness: Brightness.dark,
    );
    final palette = await _extractPalette(provider);
    return ArtworkColors(
      accent: scheme.primary,
      background: Color.alphaBlend(
        scheme.primaryContainer.withValues(alpha: 0.25),
        SegueColors.ink,
      ),
      palette: palette.isEmpty ? ArtworkColors.fallback.palette : palette,
    );
  } catch (_) {
    return ArtworkColors.fallback;
  }
});

/// Finds the cover's dominant colours: buckets pixels by hue/lightness,
/// keeps the biggest distinct buckets, then tunes them to glow nicely on a
/// dark background (a grey cover still gets gentle, non-muddy tones).
Future<List<Color>> _extractPalette(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (e, _) {
      completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return const [];

  // Bucket: 12 hue sectors × 3 lightness bands, plus 3 grey bands.
  final counts = <int, int>{};
  final sums = <int, List<double>>{};
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    if (data.getUint8(i + 3) < 128) continue;
    final c = Color.fromARGB(
      255,
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
    final hsl = HSLColor.fromColor(c);
    final band = (hsl.lightness * 3).floor().clamp(0, 2);
    final key = hsl.saturation < 0.15
        ? 100 + band
        : (hsl.hue / 30).floor() * 3 + band;
    counts[key] = (counts[key] ?? 0) + 1;
    final s = sums.putIfAbsent(key, () => [0, 0, 0]);
    s[0] += c.r;
    s[1] += c.g;
    s[2] += c.b;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

  final picked = <Color>[];
  for (final k in keys) {
    final n = counts[k]!;
    final avg = Color.from(
      alpha: 1,
      red: sums[k]![0] / n,
      green: sums[k]![1] / n,
      blue: sums[k]![2] / n,
    );
    final h = HSLColor.fromColor(avg);
    // Skip near-duplicates of what we already have.
    final dup = picked.any((p) {
      final q = HSLColor.fromColor(p);
      final dh = (q.hue - h.hue).abs();
      return (dh < 25 || dh > 335) && (q.lightness - h.lightness).abs() < 0.2;
    });
    if (dup) continue;
    picked.add(avg);
    if (picked.length == 4) break;
  }
  while (picked.isNotEmpty && picked.length < 4) {
    // Few distinct colours (e.g. monochrome cover): vary what we have.
    final h = HSLColor.fromColor(picked[picked.length % picked.length]);
    picked.add(
      h.withLightness((h.lightness + 0.18 * picked.length) % 0.8).toColor(),
    );
  }

  // Glow-friendly: mid lightness, saturation kept but never neon.
  return [
    for (final c in picked)
      () {
        final h = HSLColor.fromColor(c);
        return h
            .withLightness(h.lightness.clamp(0.34, 0.6))
            .withSaturation(
              h.saturation < 0.15
                  ? h.saturation
                  : (h.saturation * 1.4 + 0.1).clamp(0.0, 0.92),
            )
            .toColor();
      }(),
  ];
}

/// Colours of the track that is playing now (fallback while loading).
final currentColorsProvider = Provider<ArtworkColors>((ref) {
  final settings = ref.watch(settingsProvider);
  final url = ref.watch(currentTrackProvider).value?.artUri?.toString();
  final cover = url == null
      ? ArtworkColors.fallback
      : ref.watch(_colorsForUrl(url)).value ?? ArtworkColors.fallback;
  if (settings.accentFromCover) return cover;
  // Fixed accent from settings; the backdrop keeps the cover's colours.
  return ArtworkColors(
    accent: settings.accent,
    background: cover.background,
    palette: cover.palette,
  );
});
