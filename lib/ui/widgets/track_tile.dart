import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
    this.onPlayed,
  });

  /// Called when the song is tapped to play (search keeps it in history).
  final VoidCallback? onPlayed;

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
      onTap: () {
        ref.read(playerProvider).tapTrack(tracks, index, context: playContext);
        onPlayed?.call();
      },
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

  /// "Less motion": the bars stand still.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still && _c.isAnimating) _c.stop();
    if (!_still && widget.active && !_c.isAnimating) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating && !_still) _c.repeat();
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
/// One song's download progress out of the map of all of them: rebuilds
/// only when that song's number changes (every chunk of any download
/// rebuilt the badge of every row on screen).
class _ProgressOf extends StatefulWidget {
  const _ProgressOf({
    required this.progress,
    required this.keyOf,
    required this.builder,
  });

  final ValueListenable<Map<String, double>> progress;
  final String keyOf;
  final Widget Function(BuildContext context, double? p) builder;

  @override
  State<_ProgressOf> createState() => _ProgressOfState();
}

class _ProgressOfState extends State<_ProgressOf> {
  double? _p;

  @override
  void initState() {
    super.initState();
    _p = widget.progress.value[widget.keyOf];
    widget.progress.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ProgressOf old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) {
      old.progress.removeListener(_changed);
      widget.progress.addListener(_changed);
    }
    _p = widget.progress.value[widget.keyOf];
  }

  void _changed() {
    final p = widget.progress.value[widget.keyOf];
    if (p != _p && mounted) setState(() => _p = p);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _p);
}

class DownloadBadge extends ConsumerWidget {
  const DownloadBadge({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadedKeysProvider).contains(track.key);
    final accent = ref.watch(currentColorsProvider).accent;
    return _ProgressOf(
      progress: ref.read(downloadsProvider).progress,
      keyOf: track.key,
      builder: (context, p) {
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
