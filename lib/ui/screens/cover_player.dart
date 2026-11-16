import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../../core/lyrics/lyrics.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/motion.dart';
import '../widgets/output_badge.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/track_actions.dart';
import '../widgets/wavy_progress.dart';
import 'devices_screen.dart';

/// The full player with the cover filling the top of the screen and
/// melting into its own colour; everything else sits on that colour
/// below. Chosen in Settings → Player look.
class CoverPlayer extends ConsumerWidget {
  const CoverPlayer({
    super.key,
    required this.onClose,
    required this.onLyrics,
    this.lyricsOn = false,
  });

  final VoidCallback onClose;

  /// The lyrics take the cover's place (the look stays the same).
  final bool lyricsOn;

  /// Null when the song has no lyrics.
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentTrackProvider).value;
    final colors = ref.watch(currentColorsProvider);
    final player = ref.read(playerProvider);
    final track = item == null ? null : player.current;
    final liked =
        track != null && ref.watch(likedKeysProvider).contains(track.key);
    // The cover's own dark colour, so the picture fades into it.
    final base = Color.alphaBlend(
      colors.background.withValues(alpha: 0.85),
      Colors.black,
    );
    return LayoutBuilder(
      builder: (context, box) {
        // On a wide window the cover stays square in the middle.
        final cover = math.min(box.maxWidth, box.maxHeight * 0.58);
        final panelW = math.min(box.maxWidth, 560.0);
        return ColoredBox(
          color: base,
          child: Stack(
            children: [
              // The cover, blurred and darkened, under everything: the
              // panel below sits on its colours (drawn once per song).
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: 110,
                        sigmaY: 110,
                        tileMode: TileMode.clamp,
                      ),
                      child: Transform.scale(
                        scale: 1.6,
                        child: Artwork(
                          key: ValueKey('bg-${item?.artUri}'),
                          url: item?.artUri?.toString(),
                          size: math.max(box.maxWidth, box.maxHeight),
                          radius: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Darker towards the bottom, so the controls always read.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: (box.maxWidth - cover) / 2,
                width: cover,
                height: cover,
                child: ShaderMask(
                  // Solid at the top, gone at the bottom.
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, 0.62, 1],
                  ).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: AnimatedOpacity(
                    duration: SegueMotion.medium,
                    opacity: lyricsOn ? 0 : 1,
                    child: ShaderMask(
                      // A wide window: the sides melt away too.
                      shaderCallback: (r) => LinearGradient(
                        colors: const [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: box.maxWidth > cover + 2
                            ? const [0, 0.2, 0.8, 1]
                            : const [0, 0, 1, 1],
                      ).createShader(r),
                      blendMode: BlendMode.dstIn,
                      child: AnimatedSwitcher(
                        duration: SegueMotion.slow,
                        child: Artwork(
                          key: ValueKey(item?.artUri),
                          url: item?.artUri?.toString(),
                          size: cover,
                          radius: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // The handle: tap or drag down to close.
                    GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        height: 28,
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (lyricsOn && track != null) ...[
                      // Small cover and title on top, the lyrics below.
                      SizedBox(
                        width: panelW,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                          child: _Header(
                            url: item?.artUri?.toString(),
                            title: item?.title ?? '',
                            artist: item?.artist ?? '',
                            track: track,
                            liked: liked,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SizedBox(
                          width: math.min(box.maxWidth, 760.0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: LyricsView(
                              key: ValueKey('lyrics-${track.key}'),
                              track: track,
                            ),
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Center(
                      child: SizedBox(
                        width: panelW,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                          child: _Panel(
                            title: item?.title ?? '',
                            artist: item?.artist ?? '',
                            track: track,
                            liked: liked,
                            onLyrics: onLyrics,
                            lyricsOn: lyricsOn && track != null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({
    required this.title,
    required this.artist,
    required this.track,
    required this.liked,
    required this.onLyrics,
    this.lyricsOn = false,
  });

  final String title, artist;
  final Track? track;
  final bool liked;
  final VoidCallback? onLyrics;

  /// The title is in the header above the lyrics then.
  final bool lyricsOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final t = track;
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    Widget disc(Widget child, VoidCallback? onTap) => PressScale(
      scale: 0.88,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.16),
        ),
        child: child,
      ),
    );
    Widget bottom(IconData icon, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: PressScale(
        scale: 0.85,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 26,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!lyricsOn)
          Row(
            children: [
              Expanded(
                child: SoftSwitcher(
                  child: Column(
                    key: ValueKey(title + artist),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (t != null) ...[
                disc(LikeButton(track: t, liked: liked, size: 20), null),
                const SizedBox(width: 12),
                disc(
                  const Icon(Icons.more_horiz_rounded, size: 22),
                  () => showTrackActions(context, ref, t),
                ),
              ],
            ],
          ),
        if (!lyricsOn) ...[
          const SizedBox(height: 18),
          if (t != null) _LyricLine(track: t, onTap: onLyrics),
        ],
        const SizedBox(height: 8),
        const _Progress(),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Big(Icons.fast_rewind_rounded, player.skipToPrevious, 54),
            _Big(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              playing ? player.pause : player.play,
              64,
            ),
            _Big(Icons.fast_forward_rounded, player.skipToNext, 54),
          ],
        ),
        if (desktop) ...[const SizedBox(height: 14), const _VolumeRow()],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            AnimatedContainer(
              duration: SegueMotion.medium,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lyricsOn
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
              child: bottom(Icons.lyrics_rounded, onLyrics),
            ),
            bottom(Icons.devices_rounded, () => showHandoffSheet(context, ref)),
            bottom(Icons.queue_music_rounded, () => showQueueSheet(context)),
          ],
        ),
        const Center(child: OutputBadge(size: 13)),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.icon, this.onTap, this.size);

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => PressScale(
    scale: 0.82,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: AnimatedSwitcher(
        duration: SegueMotion.fast,
        child: Icon(icon, key: ValueKey(icon), size: size),
      ),
    ),
  );
}

/// The line being sung, a tap opens the lyrics.
class _LyricLine extends ConsumerWidget {
  const _LyricLine({required this.track, required this.onTap});

  final Track track;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(track)).value;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return const SizedBox(height: 4);
    }
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final i = lyrics.lineAt(pos - lyrics.shift);
    final text = lyrics.synced
        ? (i < 0 ? lyrics.lines.first.text : lyrics.lines[i].text)
        : lyrics.lines.first.text;
    return PressScale(
      scale: 0.98,
      onTap: onTap,
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: SegueMotion.medium,
                layoutBuilder: (c, prev) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...prev, ?c],
                ),
                child: Text(
                  text.isEmpty ? '♪' : text,
                  key: ValueKey(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin line that thickens under the finger, times under it: elapsed
/// on the left, what's left on the right.
class _Progress extends ConsumerWidget {
  const _Progress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final item = ref.watch(currentTrackProvider).value;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? item?.duration;
    final total = dur?.inMilliseconds ?? 0;
    final f = total == 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
    final left = dur == null ? Duration.zero : dur - pos;
    const style = TextStyle(
      fontSize: 12.5,
      color: Color(0x99FFFFFF),
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SeekLine(
          key: ValueKey(player.current?.key),
          progress: f,
          color: Colors.white.withValues(alpha: 0.9),
          onSeek: total == 0 ? null : (x) => player.seek(dur! * x),
        ),
        Row(
          children: [
            Text(formatDuration(pos), style: style),
            const Spacer(),
            Text(
              '−${formatDuration(left.isNegative ? Duration.zero : left)}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

/// Quiet and loud ends around the volume line (computers).
class _VolumeRow extends ConsumerWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final dim = Colors.white.withValues(alpha: 0.6);
    return ValueListenableBuilder<double>(
      valueListenable: player.volume,
      builder: (context, v, _) => Row(
        children: [
          Icon(Icons.volume_mute_rounded, size: 18, color: dim),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: SliderComponentShape.noThumb,
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white.withValues(alpha: 0.9),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Slider(
                  value: v,
                  onChanged: (x) {
                    player.setVolume(x);
                    ref
                        .read(libraryProvider)
                        .setMeta('volume', '${player.volume.value}');
                  },
                ),
              ),
            ),
          ),
          Icon(Icons.volume_up_rounded, size: 18, color: dim),
        ],
      ),
    );
  }
}

/// Above the lyrics: a small cover, the title and the song's buttons.
class _Header extends ConsumerWidget {
  const _Header({
    required this.url,
    required this.title,
    required this.artist,
    required this.track,
    required this.liked,
  });

  final String? url;
  final String title, artist;
  final Track track;
  final bool liked;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Artwork(url: url, size: 56, radius: 10),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
      LikeButton(track: track, liked: liked, size: 22),
      IconButton(
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: () => showTrackActions(context, ref, track),
      ),
    ],
  );
}
