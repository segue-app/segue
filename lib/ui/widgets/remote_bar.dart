import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player.dart';
import '../../core/sync/connect.dart';
import '../screens/devices_screen.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'motion.dart';

/// "Играет на MacBook": shown while another of your devices plays and this
/// one doesn't. Pause / play from here; tap for the full remote.
class RemoteBar extends ConsumerWidget {
  const RemoteBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    final localPlaying = ref.watch(playingProvider).value ?? false;
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: connect.changes,
      builder: (context, _) {
        final d = localPlaying ? null : connect.playingElsewhere;
        final track = remoteTrack(d?.remote);
        return AnimatedSwitcher(
          duration: SegueMotion.slow,
          transitionBuilder: (child, a) => SizeTransition(
            sizeFactor: a,
            child: FadeTransition(opacity: a, child: child),
          ),
          child: d == null || track == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  key: ValueKey(d.id),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: PressScale(
                    scale: 0.98,
                    onTap: () => showRemoteControl(context, d.id),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: 0.18),
                          SegueColors.surfaceHigh,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Artwork(url: track.artworkUrl, size: 40, radius: 10),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Icon(
                                      platformIcon(d.platform),
                                      size: 14,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Играет на ${d.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: accent,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Слушать здесь',
                            onPressed: () => connect.takeFrom(d.id),
                            icon: const Icon(Icons.download_rounded),
                          ),
                          IconButton(
                            onPressed: () => connect.command(
                              d.id,
                              d.playing ? 'pause' : 'play',
                            ),
                            icon: Icon(
                              d.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
