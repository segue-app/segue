import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import 'motion.dart';

/// Mute button and volume slider; in the bar and in the full player.
class VolumeSlider extends ConsumerWidget {
  const VolumeSlider({super.key, this.width = 104});

  final double width;

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
            width: width,
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

/// A speaker button whose volume pops up over it, as in Yandex Music: on
/// hover (or a tap) a slim vertical slider shows, and hides a moment after
/// the pointer leaves. The mouse wheel over it turns the volume too; a
/// click mutes.
class HoverVolume extends ConsumerStatefulWidget {
  const HoverVolume({super.key, this.size = 44});

  final double size;

  @override
  ConsumerState<HoverVolume> createState() => _HoverVolumeState();
}

class _HoverVolumeState extends ConsumerState<HoverVolume> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;
  double _before = 1;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    if (!_portal.isShowing) setState(_portal.show);
  }

  void _leave() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _portal.isShowing) setState(_portal.hide);
    });
  }

  void _set(double v) {
    final player = ref.read(playerProvider);
    player.setVolume(v.clamp(0.0, 1.0));
    ref.read(libraryProvider).setMeta('volume', '${player.volume.value}');
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final popup = ValueListenableBuilder<double>(
      valueListenable: player.volume,
      builder: (context, v, _) => Container(
        width: 44,
        height: 168,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF0222226),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              '${(v * 100).round()}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: accent,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(value: v, onChanged: _set),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        // Positioned at the corner so the follower is only as big as the
        // popup: its bottom centre then sits just above the speaker.
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -8),
            child: MouseRegion(
              onEnter: (_) => _show(),
              onExit: (_) => _leave(),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - t)),
                    child: child,
                  ),
                ),
                child: Material(type: MaterialType.transparency, child: popup),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _leave(),
          child: Listener(
            // The wheel turns the volume.
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                _show();
                _set(player.volume.value - e.scrollDelta.dy / 800);
                _leave();
              }
            },
            child: ValueListenableBuilder<double>(
              valueListenable: player.volume,
              builder: (context, v, _) => PressScale(
                scale: 0.86,
                onTap: () {
                  // Mute, and back to where it was.
                  if (v > 0) {
                    _before = v;
                    _set(0);
                  } else {
                    _set(_before > 0 ? _before : 1);
                  }
                  _show();
                  _leave();
                },
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    v == 0
                        ? Icons.volume_off_rounded
                        : v < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                    size: widget.size * 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
