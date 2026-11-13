import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/downloads/downloads.dart';
import '../../core/library/library.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'motion.dart';
import 'track_actions.dart';
import 'slow_ticker.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.tracks,
    required this.index,
    this.sourceLabel,
    this.onRemove,
    this.playContext,
  });

  /// Where this list is ('liked', 'playlist:ID'), passed to the player.
  final String? playContext;

  final List<Track> tracks;
  final int index;

  /// Shown as a small tag in the merged list so you know where it plays from.
  final String? sourceLabel;

  /// Set inside a playlist: adds "remove from playlist" to the menu.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tracks[index];
    // Each row listens only for what concerns it: a new track, a like or
    // a new accent colour redraws two rows, not the whole list.
    final isCurrent = ref.watch(
      currentTrackProvider.select((v) => v.value?.id == t.key),
    );
    final playing =
        isCurrent && ref.watch(playingProvider.select((v) => v.value ?? false));
    final accent = isCurrent
        ? ref.watch(currentColorsProvider.select((c) => c.accent))
        : SegueColors.text;
    final liked = ref.watch(
      likedKeysProvider.select((keys) => keys.contains(t.key)),
    );

    return PressScale(
      scale: 0.98,
      hoverRadius: 18,
      onWarm: () => ref.read(playerProvider).warm(t),
      onTap: () => ref
          .read(playerProvider)
          .tapTrack(tracks, index, context: playContext),
      onLongPress: () => showTrackActions(context, ref, t, onRemove: onRemove),
      child: AnimatedContainer(
        duration: SegueMotion.medium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent
              ? accent.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Artwork(url: t.artworkUrl, size: 52, radius: 14),
                AnimatedOpacity(
                  opacity: isCurrent ? 1 : 0,
                  duration: SegueMotion.medium,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: EqualizerBars(active: playing, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: SegueMotion.medium,
                    style: TextStyle(
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? accent : SegueColors.text,
                    ),
                    child: Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (sourceLabel != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sourceLabel!,
                            style: const TextStyle(
                              color: SegueColors.textDim,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SegueColors.textDim,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DownloadBadge(track: t),
            LikeButton(track: t, liked: liked, size: 20),
            Text(
              formatDuration(t.duration),
              style: const TextStyle(
                color: SegueColors.textDim,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            PressScale(
              scale: 0.85,
              onTap: () =>
                  showTrackActions(context, ref, t, onRemove: onRemove),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 2, 8),
                child: Icon(
                  Icons.more_horiz_rounded,
                  color: SegueColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three bouncing bars on the playing track; they settle when paused.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({super.key, required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SlowTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) {
      _c.animateTo(0, duration: SegueMotion.medium);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height:
                  6 +
                  14 *
                      (0.5 +
                          0.5 * math.sin((_c.value + i * 0.33) * 2 * math.pi)) *
                      (widget.active ? 1 : 0.3),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tiny indicator: a ring while downloading, a check-mark arrow once the
/// track is on the device. Nothing otherwise.
class DownloadBadge extends ConsumerWidget {
  const DownloadBadge({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadedKeysProvider).contains(track.key);
    final accent = ref.watch(currentColorsProvider).accent;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: ref.read(downloadsProvider).progress,
      builder: (context, busy, _) {
        final p = busy[track.key];
        final Widget child;
        if (p != null) {
          child = SizedBox.square(
            key: const ValueKey('busy'),
            dimension: 16,
            child: CircularProgressIndicator(
              value: p == 0 ? null : p,
              strokeWidth: 2,
              color: accent,
            ),
          );
        } else if (downloaded) {
          child = Icon(
            Icons.download_done_rounded,
            key: const ValueKey('done'),
            size: 18,
            color: accent,
          );
        } else {
          child = const SizedBox(key: ValueKey('none'));
        }
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: AnimatedSwitcher(duration: SegueMotion.medium, child: child),
        );
      },
    );
  }
}
