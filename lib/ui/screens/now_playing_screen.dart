import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../../core/models/track.dart';
import '../../core/settings/settings.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../app_nav.dart';
import '../widgets/artwork.dart';
import '../widgets/depth.dart';
import 'devices_screen.dart';
import '../widgets/living_backdrop.dart';
import '../widgets/lyrics_view.dart';
import '../../core/lyrics/lyrics.dart';
import '../widgets/motion.dart';
import '../widgets/play_button.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/sound_panel.dart';
import '../widgets/track_actions.dart';
import '../widgets/wavy_progress.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
    opaque: false,
    transitionDuration: SegueMotion.slow,
    reverseTransitionDuration: SegueMotion.medium,
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  /// Vertical drag offset for swipe-down-to-close.
  double _dragY = 0;

  /// Lyrics replace the cover while on.
  bool _lyrics = false;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentTrackProvider).value;
    final playing = ref.watch(playingProvider).value ?? false;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(durationProvider).value ?? item?.duration ?? Duration.zero;
    final colors = ref.watch(currentColorsProvider);
    final player = ref.read(playerProvider);
    final art = item?.artUri?.toString();
    // Watch the item so the track updates with it.
    final track = item == null ? null : player.current;
    final likedKeys = ref.watch(likedKeysProvider);
    final hasPeers = ref.watch(peersProvider).isNotEmpty;
    final settings = ref.watch(settingsProvider);
    // Fetching here also preloads lyrics before they're opened.
    final lyricsState = track == null ? null : ref.watch(lyricsProvider(track));
    final hasLyrics = lyricsState?.value?.lines.isNotEmpty ?? false;
    final showLyrics =
        _lyrics && (hasLyrics || (lyricsState?.isLoading ?? false));

    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return GestureDetector(
      onVerticalDragUpdate: (d) =>
          setState(() => _dragY = (_dragY + d.delta.dy).clamp(0, 400)),
      onVerticalDragEnd: (d) {
        if (_dragY > 120 || d.primaryVelocity! > 700) {
          Navigator.of(context).pop();
        } else {
          setState(() => _dragY = 0);
        }
      },
      child: AnimatedContainer(
        duration: _dragY == 0 ? SegueMotion.medium : Duration.zero,
        curve: SegueMotion.spring,
        transform: Matrix4.translationValues(0, _dragY, 0),
        child: Scaffold(
          backgroundColor: SegueColors.ink,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Living backdrop built from the cover's colours.
              RepaintBoundary(
                child: LivingBackdrop(
                  palette: colors.palette,
                  base: colors.background,
                  playing: playing,
                  speed: settings.reduceMotion ? 0 : settings.backdropSpeed,
                  intensity: settings.backdropIntensity,
                  style: settings.backdrop,
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final lyricsOn = showLyrics && track != null;
                    final wide = box.maxWidth >= 900;
                    final topBar = _TopBar(
                      onClose: () => Navigator.of(context).pop(),
                      onMore: track == null
                          ? null
                          : () => showTrackActions(context, ref, track),
                      // Only with somewhere to send the music to.
                      onDevices: hasPeers
                          ? () => showHandoffSheet(context, ref)
                          : null,
                      lyricsOn: showLyrics,
                      // Grey and inert when the track has no lyrics.
                      onLyrics: hasLyrics
                          ? () => setState(() => _lyrics = !_lyrics)
                          : null,
                    );
                    final info = _TitleRow(
                      title: item?.title ?? '',
                      artist: item?.artist ?? '',
                      itemKey: item?.id,
                      onArtist:
                          track == null || track.source == SourceKind.local
                          ? null
                          : () =>
                                AppNav.artistByName(context, ref, track.artist),
                      like: track == null
                          ? null
                          : LikeButton(
                              track: track,
                              liked: likedKeys.contains(track.key),
                              size: 28,
                            ),
                    );
                    final controls = _Controls(
                      progress: progress,
                      position: position,
                      duration: duration,
                      playing: playing,
                      wavy: settings.wavyProgress,
                      accent: colors.accent,
                    );
                    final lyrics = lyricsOn
                        ? LyricsView(
                            key: ValueKey('lyrics-${track.key}'),
                            track: track,
                          )
                        : null;

                    // Wide screens: one layout for both states, animated.
                    // Lyrics off: the cover panel sits in the middle.
                    // Lyrics on: it slides left and turns in 3D while the
                    // lyrics slide in from the right; closing reverses it.
                    if (wide) {
                      final d3 = settings.depth3d;
                      final side = math.max(40.0, box.maxWidth * 0.04);
                      final contentW = math.min(
                        box.maxWidth - side * 2,
                        1360.0,
                      );
                      final leftW = math.min(420.0, contentW * 0.34);
                      const gap = 80.0;
                      final rightW = contentW - leftW - gap;
                      return Column(
                        children: [
                          const SizedBox(height: 8),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: side),
                            child: topBar,
                          ),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: contentW,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: lyricsOn ? 1 : 0),
                                  duration: const Duration(milliseconds: 750),
                                  curve: Curves.easeInOutCubic,
                                  builder: (context, t, _) {
                                    final coverX =
                                        (contentW - leftW) / 2 * (1 - t);
                                    // Keep lyrics mounted while they fade out.
                                    final showLyricsPanel =
                                        t > 0.01 && hasLyrics && track != null;
                                    return Stack(
                                      children: [
                                        Positioned(
                                          left: coverX,
                                          top: 0,
                                          bottom: 0,
                                          width: leftW,
                                          child: Transform(
                                            alignment: Alignment.centerLeft,
                                            transform: d3
                                                ? perspective(y: -0.13 * t)
                                                : Matrix4.identity(),
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: _CoverArea(
                                                    art: art,
                                                    playing: playing,
                                                  ),
                                                ),
                                                const SizedBox(height: 20),
                                                info,
                                                const SizedBox(height: 18),
                                                controls,
                                                const SizedBox(height: 28),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (showLyricsPanel)
                                          Positioned(
                                            left: leftW + gap + 120 * (1 - t),
                                            top: 0,
                                            bottom: 0,
                                            width: rightW,
                                            child: Opacity(
                                              opacity: t,
                                              child: Transform(
                                                alignment:
                                                    Alignment.centerRight,
                                                transform: d3
                                                    ? perspective(
                                                        y:
                                                            0.13 * t +
                                                            0.25 * (1 - t),
                                                      )
                                                    : Matrix4.identity(),
                                                child: LyricsView(
                                                  key: ValueKey(
                                                    'lyrics-${track.key}',
                                                  ),
                                                  track: track,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              topBar,
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 550),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: ScaleTransition(
                                          scale: Tween(
                                            begin: 0.94,
                                            end: 1.0,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                  child: lyrics != null
                                      // Phone + lyrics: lyrics on top, a small
                                      // cover with the title under them, next
                                      // to the controls.
                                      ? Column(
                                          key: const ValueKey('lyrics'),
                                          children: [
                                            Expanded(child: lyrics),
                                            const SizedBox(height: 10),
                                            _MiniHeader(
                                              art: art,
                                              title: item?.title ?? '',
                                              artist: item?.artist ?? '',
                                              like: info.like,
                                            ),
                                          ],
                                        )
                                      : _CoverArea(
                                          key: const ValueKey('cover'),
                                          art: art,
                                          playing: playing,
                                        ),
                                ),
                              ),
                              // The title folds away smoothly when lyrics
                              // open (the mini header shows it instead).
                              AnimatedSize(
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeInOutCubic,
                                child: lyrics == null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: info,
                                      )
                                    : const SizedBox(width: double.infinity),
                              ),
                              const SizedBox(height: 18),
                              controls,
                              const SizedBox(height: 28),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big cover: fills the space it gets, breathes with play/pause and
/// crossfades between tracks. Hides on tiny windows.
class _CoverArea extends StatelessWidget {
  const _CoverArea({super.key, required this.art, required this.playing});

  final String? art;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(c.maxWidth, c.maxHeight - 32);
        if (size < 96) return const SizedBox();
        return Center(
          child: AnimatedScale(
            scale: playing ? 1 : 0.86,
            duration: SegueMotion.slow,
            curve: SegueMotion.spring,
            child: AnimatedContainer(
              duration: SegueMotion.slow,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: playing ? 0.5 : 0.3),
                    blurRadius: playing ? 48 : 24,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              // One Hero outside the switcher: two heroes with the same tag
              // must never coexist.
              child: Hero(
                tag: 'artwork',
                child: AnimatedSwitcher(
                  duration: SegueMotion.slow,
                  switchInCurve: SegueMotion.ease,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Artwork(
                    key: ValueKey(art),
                    url: art,
                    size: size,
                    radius: 28,
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

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.artist,
    required this.itemKey,
    required this.like,
    this.onArtist,
  });

  final String title;
  final String artist;
  final String? itemKey;
  final Widget? like;

  /// Tapping the artist opens their page.
  final VoidCallback? onArtist;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SoftSwitcher(
            child: Column(
              key: ValueKey(itemKey),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                MouseRegion(
                  cursor: onArtist == null
                      ? MouseCursor.defer
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onArtist,
                    child: Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ?like,
      ],
    );
  }
}

/// Phone + lyrics: small cover, title and artist under the lyrics.
class _MiniHeader extends StatelessWidget {
  const _MiniHeader({
    required this.art,
    required this.title,
    required this.artist,
    required this.like,
  });

  final String? art;
  final String title;
  final String artist;
  final Widget? like;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Artwork(url: art, size: 64, radius: 14),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
        ?like,
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({
    required this.progress,
    required this.position,
    required this.duration,
    required this.playing,
    required this.wavy,
    required this.accent,
  });

  final double progress;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool wavy;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    return Column(
      children: [
        WavyProgress(
          progress: progress,
          // The wave can be switched off in settings.
          playing: playing && wavy,
          color: accent,
          onSeek: duration == Duration.zero
              ? null
              : (f) => player.seek(duration * f),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Time(formatDuration(position)),
              _Time(formatDuration(duration)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundIcon(
              icon: Icons.skip_previous_rounded,
              onTap: player.skipToPrevious,
            ),
            PlayButton(
              playing: playing,
              color: accent,
              onPressed: playing ? player.pause : player.play,
            ),
            _RoundIcon(icon: Icons.skip_next_rounded, onTap: player.skipToNext),
          ],
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onClose,
    required this.onMore,
    required this.lyricsOn,
    required this.onLyrics,
    required this.onDevices,
  });

  final VoidCallback onClose;
  final VoidCallback? onMore;
  final bool lyricsOn;
  final VoidCallback? onLyrics;
  final VoidCallback? onDevices;

  @override
  Widget build(BuildContext context) {
    // The title is centred on the screen, not between the buttons: there
    // is one button on the left and up to five on the right.
    // Shown only when it fits between the left button and the (up to
    // five) right ones, so the icons never cover it.
    return LayoutBuilder(
      builder: (context, c) => Stack(
        alignment: Alignment.center,
        children: [
          if (c.maxWidth >= 2 * (5 * 52) + 150)
            const IgnorePointer(
              child: Text(
                'Сейчас играет',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Color(0xB3FFFFFF),
                ),
              ),
            ),
          _buttons(context),
        ],
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    return Row(
      children: [
        _RoundIcon(
          icon: Icons.keyboard_arrow_down_rounded,
          onTap: onClose,
          size: 44,
        ),
        const Spacer(),
        _RoundIcon(
          icon: Icons.queue_music_rounded,
          onTap: () => showQueueSheet(context),
          size: 44,
        ),
        const SizedBox(width: 8),
        _RoundIcon(
          icon: Icons.equalizer_rounded,
          onTap: () => showSoundSheet(context),
          size: 44,
        ),
        const SizedBox(width: 8),
        if (onDevices != null) ...[
          _RoundIcon(icon: Icons.devices_rounded, onTap: onDevices, size: 44),
          const SizedBox(width: 8),
        ],
        AnimatedContainer(
          duration: SegueMotion.medium,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lyricsOn ? Colors.white : Colors.transparent,
          ),
          child: _RoundIcon(
            icon: Icons.lyrics_rounded,
            onTap: onLyrics,
            size: 44,
            color: lyricsOn ? SegueColors.ink : Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        onMore == null
            ? const SizedBox(width: 44)
            : _RoundIcon(
                icon: Icons.more_horiz_rounded,
                onTap: onMore!,
                size: 44,
              ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.size = 60,
    this.color = Colors.white,
  });

  final IconData icon;

  /// Null shows the button greyed out and ignores taps.
  final VoidCallback? onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: onTap == null ? 0.35 : 1,
      duration: SegueMotion.medium,
      child: PressScale(
        onTap: onTap,
        scale: 0.86,
        child: ClipOval(
          child: lightEffects
              ? Container(
                  width: size,
                  height: size,
                  color: Colors.white.withValues(alpha: 0.12),
                  child: Icon(icon, size: size * 0.55, color: color),
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    width: size,
                    height: size,
                    color: Colors.white.withValues(alpha: 0.08),
                    child: Icon(icon, size: size * 0.55, color: color),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Colors.white.withValues(alpha: 0.55),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
