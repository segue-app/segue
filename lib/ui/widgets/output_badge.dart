import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Играет на Xiaomi": shown wherever the player is, while the music plays
/// on another device and this one is its remote. Nothing otherwise.
class OutputBadge extends ConsumerWidget {
  const OutputBadge({super.key, this.size = 13});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ValueListenableBuilder<String?>(
      valueListenable: player.output,
      builder: (context, name, _) => AnimatedSize(
        duration: SegueMotion.medium,
        child: name == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cast_connected_rounded,
                      size: size + 2,
                      color: accent,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Играет на {0}'.trArgs([name]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: size,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
