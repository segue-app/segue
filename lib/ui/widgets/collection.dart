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
import 'track_tile.dart';

import 'package:segue/core/l10n/l10n.dart';

/// 2×2 collage of the first covers, or a gradient tile with an icon.
class CoverCollage extends StatelessWidget {
  const CoverCollage({
    super.key,
    required this.urls,
    required this.size,
    this.radius = 20,
    this.icon = Icons.queue_music_rounded,
    this.gradient,
  });

  final List<String?> urls;
  final double size;
  final double radius;
  final IconData icon;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final covers = urls.whereType<String>().toSet().take(4).toList();
    if (gradient != null || covers.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: SegueColors.surfaceHigh,
          gradient: gradient,
        ),
        child: Icon(
          icon,
          size: size * 0.4,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      );
    }
    if (covers.length < 4) {
      return Artwork(url: covers.first, size: size, radius: radius);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final u in covers) Artwork(url: u, size: half, radius: 0),
          ],
        ),
      ),
    );
  }
}

/// Header + play/shuffle + track list. Used for playlists and liked songs.
class TrackCollectionView extends ConsumerWidget {
  const TrackCollectionView({
    super.key,
    required this.title,
    required this.tracks,
    required this.cover,
    this.subtitle,
    this.actions = const [],
    this.onRemove,
    this.onReorder,
    this.emptyText,
  });

  final String title;
  final String? subtitle;
  final List<Track> tracks;
  final Widget cover;
  final List<Widget> actions;
  final void Function(Track track)? onRemove;

  /// Your own playlists: tracks can be dragged into another order
  /// (from, to as the final index).
  final void Function(int from, int to)? onReorder;
  final String? emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(currentColorsProvider).accent;
    final player = ref.read(playerProvider);
    final wide = MediaQuery.sizeOf(context).width > 600;

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PillButton(
          icon: Icons.play_arrow_rounded,
          label: 'Слушать'.tr,
          color: accent,
          filled: true,
          onTap: tracks.isEmpty ? null : () => player.playList(tracks, 0),
        ),
        _PillButton(
          icon: Icons.shuffle_rounded,
          label: 'Вперемешку'.tr,
          color: accent,
          onTap: tracks.isEmpty
              ? null
              : () => player.playList([...tracks]..shuffle(), 0),
        ),
        ...actions,
      ],
    );

    final info = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle ?? tracksLabel(tracks.length),
          style: const TextStyle(
            color: SegueColors.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        buttons,
      ],
    );

    // Wide: cover left, info right. Phone: stacked and centred. (No flex
    // children in the stacked case: the list gives unbounded height.)
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                cover,
                const SizedBox(width: 24),
                Expanded(child: info),
              ],
            )
          : Column(children: [cover, const SizedBox(height: 18), info]),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        if (tracks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                emptyText ?? 'Здесь пока пусто'.tr,
                style: const TextStyle(color: SegueColors.textDim),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            sliver: onReorder != null
                ? SliverReorderableList(
                    itemCount: tracks.length,
                    onReorderItem: (from, to) => onReorder!(from, to),
                    proxyDecorator: (child, _, _) => Material(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      child: child,
                    ),
                    itemBuilder: (context, i) => Row(
                      key: ValueKey(tracks[i].key),
                      children: [
                        Expanded(
                          child: TrackTile(
                            tracks: tracks,
                            index: i,
                            onRemove: onRemove == null
                                ? null
                                : () => onRemove!(tracks[i]),
                          ),
                        ),
                        // Grab here to move the song (a long press on
                        // the song itself opens its menu).
                        ReorderableDragStartListener(
                          index: i,
                          child: const MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 14,
                              ),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: SegueColors.textDim,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : SliverList.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) => StaggeredEntrance(
                      index: i % 12,
                      child: TrackTile(
                        tracks: tracks,
                        index: i,
                        onRemove: onRemove == null
                            ? null
                            : () => onRemove!(tracks[i]),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? SegueColors.ink : SegueColors.text;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: SegueMotion.slow,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: filled ? color : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small round icon button used in collection headers.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: PressScale(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22),
        ),
      ),
    );
  }
}

const likedGradient = LinearGradient(
  colors: [Color(0xFFFF6B81), Color(0xFF8E5CFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Header button: download every track of a list that isn't saved yet.
class DownloadAllButton extends ConsumerWidget {
  const DownloadAllButton({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(downloadedKeysProvider);
    final missing = [
      for (final t in tracks)
        if (t.source != SourceKind.local && !saved.contains(t.key)) t,
    ];
    return HeaderIconButton(
      icon: missing.isEmpty
          ? Icons.download_done_rounded
          : Icons.download_rounded,
      onTap: () {
        if (missing.isEmpty) return;
        ref.read(downloadsProvider).download(missing);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Скачиваем {0}'.trArgs([tracksLabel(missing.length)]),
            ),
          ),
        );
      },
    );
  }
}
