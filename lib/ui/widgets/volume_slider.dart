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
