import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'jam_sheet.dart';
import '../../core/models/track.dart';

import 'package:segue/core/l10n/l10n.dart';

/// The play queue: drag to reorder, swipe to remove, tap to jump.
Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 620),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.78,
    child: const _Queue(),
  ),
);

class _Queue extends ConsumerWidget {
  const _Queue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: Listenable.merge([player.queueVersion, player.waveTitle]),
      builder: (context, _) {
        final tracks = player.tracks;
        final current = player.index;
        final wave = player.waveTitle.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Очередь'.tr,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Слушать вместе'.tr,
                    onPressed: () {
                      Navigator.pop(context);
                      showJamSheet(context);
                    },
                    icon: const Icon(Icons.groups_rounded),
                  ),
                  if (wave != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.waves_rounded, size: 16, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            wave.tr,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (wave != null)
              Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
                child: Text(
                  'Волна бесконечная: новые треки добавятся сами'.tr,
                  style: TextStyle(color: SegueColors.textDim, fontSize: 12.5),
                ),
              ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                buildDefaultDragHandles: false,
                itemCount: tracks.length,
                onReorderItem: player.moveQueueItem,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  final isCurrent = i == current;
                  final tile = Material(
                    color: isCurrent
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      contentPadding: const EdgeInsets.only(left: 10, right: 4),
                      leading: Opacity(
                        opacity: i < current ? 0.45 : 1,
                        child: Artwork(url: t.artworkUrl, size: 44, radius: 10),
                      ),
                      title: Text(
                        t.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? accent
                              : (i < current
                                    ? SegueColors.textDim
                                    : SegueColors.text),
                        ),
                      ),
                      subtitle: Text(
                        t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: SegueColors.textDim),
                      ),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: SegueColors.textDim,
                          ),
                        ),
                      ),
                      onTap: () => player.skipToQueueItem(i),
                    ),
                  );
                  return KeyedSubtree(
                    key: ValueKey('${t.key}#$i'),
                    child: isCurrent
                        ? tile
                        : Dismissible(
                            key: ValueKey('d-${t.key}#$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete_outline_rounded),
                            ),
                            onDismissed: (_) => player.removeQueueItemAt(i),
                            child: tile,
                          ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
