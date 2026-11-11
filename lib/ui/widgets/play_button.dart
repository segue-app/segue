import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'motion.dart';

/// Play/pause button that morphs: a circle when paused, a soft rounded
/// square while playing, with an animated play↔pause icon.
class PlayButton extends StatefulWidget {
  const PlayButton({
    super.key,
    required this.playing,
    required this.onPressed,
    required this.color,
    this.size = 76,
  });

  final bool playing;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton>
    with SingleTickerProviderStateMixin {
  late final _icon = AnimationController(
    vsync: this,
    duration: SegueMotion.medium,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayButton old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _icon.forward() : _icon.reverse();
    }
  }

  @override
  void dispose() {
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return PressScale(
      onTap: widget.onPressed,
      scale: 0.9,
      child: AnimatedContainer(
        duration: SegueMotion.slow,
        curve: SegueMotion.spring,
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.playing ? s * 0.3 : s / 2),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(
                alpha: widget.playing ? 0.45 : 0.2,
              ),
              blurRadius: widget.playing ? 32 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: AnimatedIcon(
            icon: AnimatedIcons.play_pause,
            progress: CurvedAnimation(parent: _icon, curve: SegueMotion.ease),
            size: s * 0.46,
            color: SegueColors.ink,
          ),
        ),
      ),
    );
  }
}
