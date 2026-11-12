import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:audio_service/audio_service.dart';

import '../../core/library/library.dart';
import '../../core/player/player.dart';
import '../../core/settings/settings.dart';
import '../screens/now_playing_screen.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'motion.dart';
import 'output_badge.dart';
import 'queue_sheet.dart';
import 'sound_panel.dart';
import 'track_actions.dart';
import 'wavy_progress.dart';

/// Frosted-glass player pinned to the bottom, tinted by the cover colours.
/// Slides in the first time something plays; tap to open the full player.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentTrackProvider).value;
    return AnimatedSwitcher(
      duration: SegueMotion.slow,
      switchInCurve: SegueMotion.spring,
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: anim,
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.6),
            end: Offset.zero,
          ).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
      ),
      child: item == null
          ? const SizedBox(width: double.infinity)
          : const _Bar(),
    );
  }
}

class _Bar extends ConsumerWidget {
  const _Bar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentTrackProvider).value!;
    final colors = ref.watch(currentColorsProvider);
    final glass = ref.watch(settingsProvider).glass && !lightEffects;

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: PressScale(
            scale: wide ? 1 : 0.98,
            onTap: () => Navigator.of(context).push(NowPlayingScreen.route()),
            child: DecoratedBox(
              // A soft glow in the cover's colour lifts the bar off the page.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.16),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: glass
                      ? ImageFilter.blur(sigmaX: 24, sigmaY: 24)
                      : ImageFilter.blur(),
                  child: AnimatedContainer(
                    duration: SegueMotion.slow,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.alphaBlend(
                            colors.accent.withValues(alpha: 0.14),
                            SegueColors.surfaceHigh.withValues(alpha: 0.82),
                          ),
                          Color.alphaBlend(
                            colors.background.withValues(alpha: 0.5),
                            SegueColors.surfaceHigh.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: wide ? _Wide(item: item) : _Compact(item: item),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cover, title and artist; shared by both layouts.
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.item, this.size = 46});

  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Hero(
          tag: 'artwork',
          child: AnimatedSwitcher(
            duration: SegueMotion.medium,
            child: Artwork(
              key: ValueKey(item.artUri),
              url: item.artUri?.toString(),
              size: size,
              radius: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SoftSwitcher(
            child: Column(
              key: ValueKey(item.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  item.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SegueColors.textDim,
                    fontSize: 13,
                  ),
                ),
                const OutputBadge(size: 11.5),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Phone: cover, title, play/pause, next and a thin progress line.
class _Compact extends ConsumerWidget {
  const _Compact({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? item.duration;
    final accent = ref.watch(currentColorsProvider).accent;
    final player = ref.read(playerProvider);
    final progress = (duration == null || duration.inMilliseconds == 0)
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 6, 0),
          child: Row(
            children: [
              Expanded(child: _TrackInfo(item: item)),
              PressScale(
                onTap: player.skipToPrevious,
                scale: 0.85,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.skip_previous_rounded, size: 28),
                ),
              ),
              _MiniPlayPause(
                playing: playing,
                onTap: playing ? player.pause : player.play,
              ),
              PressScale(
                onTap: player.skipToNext,
                scale: 0.85,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.skip_next_rounded, size: 28),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: SeekLine(
            // A new track starts with a fresh bar (no leftover seek).
            key: ValueKey(player.current?.key),
            progress: progress,
            color: accent,
            onSeek: duration == null || duration == Duration.zero
                ? null
                : (f) => player.seek(duration * f),
          ),
        ),
      ],
    );
  }
}

/// Desktop: track and like on the left, transport with a seekable wave in
/// the middle, lyrics / queue / volume on the right.
class _Wide extends ConsumerWidget {
  const _Wide({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final accent = ref.watch(currentColorsProvider).accent;
    final player = ref.read(playerProvider);
    final track = player.current;
    final liked =
        track != null && ref.watch(likedKeysProvider).contains(track.key);

    Widget icon(IconData i, VoidCallback onTap, {double size = 22}) =>
        PressScale(
          scale: 0.85,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              i,
              size: size,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(child: _TrackInfo(item: item, size: 54)),
                if (track != null)
                  LikeButton(track: track, liked: liked, size: 20),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon(
                      Icons.skip_previous_rounded,
                      player.skipToPrevious,
                      size: 26,
                    ),
                    const SizedBox(width: 6),
                    PressScale(
                      scale: 0.9,
                      onTap: playing ? player.pause : player.play,
                      child: AnimatedContainer(
                        duration: SegueMotion.slow,
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: SegueColors.ink,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    icon(Icons.skip_next_rounded, player.skipToNext, size: 26),
                  ],
                ),
                _Seek(item: item),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                icon(Icons.queue_music_rounded, () => showQueueSheet(context)),
                icon(Icons.equalizer_rounded, () => showSoundSheet(context)),
                const SizedBox(width: 4),
                const _Volume(),
                const SizedBox(width: 4),
                icon(
                  Icons.open_in_full_rounded,
                  () => Navigator.of(context).push(NowPlayingScreen.route()),
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Times and the seekable wave. On its own so that position updates only
/// rebuild this row.
class _Seek extends ConsumerWidget {
  const _Seek({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = ref.watch(durationProvider).value ?? item.duration;
    final accent = ref.watch(currentColorsProvider).accent;
    final wavy = ref.watch(settingsProvider).wavyProgress;
    final player = ref.read(playerProvider);
    final progress = (duration == null || duration.inMilliseconds == 0)
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    const style = TextStyle(
      color: SegueColors.textDim,
      fontSize: 11.5,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(formatDuration(position), style: style),
        ),
        Expanded(
          child: SizedBox(
            height: 22,
            child: WavyProgress(
              // A new track starts with a fresh bar (no leftover seek).
              key: ValueKey(player.current?.key),
              progress: progress,
              playing: playing && wavy,
              color: accent,
              onSeek: duration == null || duration == Duration.zero
                  ? null
                  : (f) => player.seek(duration * f),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            formatDuration(duration),
            style: style,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _Volume extends ConsumerWidget {
  const _Volume();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    void set(double v) {
      player.setVolume(v);
      ref.read(libraryProvider).setMeta('volume', '${player.volume.value}');
    }

    return ValueListenableBuilder<double>(
      valueListenable: player.volume,
      builder: (context, v, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PressScale(
            scale: 0.85,
            onTap: () => set(v > 0 ? 0 : 1),
            child: Icon(
              v == 0
                  ? Icons.volume_off_rounded
                  : v < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(
            width: 104,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: Colors.white,
              ),
              child: Slider(value: v, onChanged: set),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayPause extends StatefulWidget {
  const _MiniPlayPause({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  State<_MiniPlayPause> createState() => _MiniPlayPauseState();
}

class _MiniPlayPauseState extends State<_MiniPlayPause>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: SegueMotion.medium,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(_MiniPlayPause old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: widget.onTap,
      scale: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedIcon(
          icon: AnimatedIcons.play_pause,
          progress: CurvedAnimation(parent: _c, curve: SegueMotion.ease),
          size: 30,
        ),
      ),
    );
  }
}
