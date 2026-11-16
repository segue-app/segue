import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../../core/models/track.dart';
import '../../core/library/search_history.dart';
import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

import 'package:segue/core/l10n/l10n.dart';

import '../../core/sync/shared_playlists.dart';
import '../widgets/shared_playlist_sheet.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  static Route<void> route(String id) => MaterialPageRoute(
    settings: RouteSettings(name: '/playlist/$id'),
    builder: (_) => PlaylistScreen(playlistId: id),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref
        .watch(playlistsProvider)
        .where((p) => p.id == playlistId)
        .firstOrNull;
    final tracks = ref.watch(playlistTracksProvider(playlistId));
    final library = ref.read(libraryProvider);
    if (playlist != null) {
      rememberOpened(
        ref,
        HistoryItem(
          kind: HistoryKind.playlist,
          id: playlistId,
          title: playlist.name,
          subtitle: 'Плейлист',
          image: tracks.firstOrNull?.artworkUrl,
        ),
      );
    }
    final size = MediaQuery.sizeOf(context).width > 600 ? 200.0 : 180.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: playlist == null
          ? const SizedBox()
          : TrackCollectionView(
              title: playlist.name,
              tracks: tracks,
              cover: CoverCollage(
                urls: [for (final t in tracks) t.artworkUrl],
                size: size,
              ),
              emptyText: 'Добавляй треки через ••• → «Добавить в плейлист»'.tr,
              playContext: 'playlist:$playlistId',
              onRemove: (t) => library.removeFromPlaylist(playlistId, t),
              onReorder: (from, to) =>
                  library.movePlaylistItem(playlistId, tracks, from, to),
              subtitle: ref.watch(sharedCodesProvider).containsKey(playlistId)
                  ? 'Совместный плейлист'.tr
                  : null,
              actions: [
                _LikeAllButton(tracks: tracks),
                DownloadAllButton(tracks: tracks),
                HeaderIconButton(
                  icon: Icons.group_add_rounded,
                  onTap: () => showSharedPlaylistSheet(context, playlistId),
                ),
                HeaderIconButton(
                  icon: Icons.edit_rounded,
                  onTap: () async {
                    final name = await askPlaylistName(
                      context,
                      initial: playlist.name,
                    );
                    if (name != null) library.renamePlaylist(playlistId, name);
                  },
                ),
                HeaderIconButton(
                  icon: Icons.delete_outline_rounded,
                  onTap: () async {
                    final ok = await _confirmDelete(context, playlist.name);
                    if (ok && context.mounted) {
                      library.deletePlaylist(playlistId);
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async =>
      await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (d) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text('Удалить «{0}»?'.trArgs([name])),
          content: Text('Треки останутся в поиске и в любимых.'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text('Отмена'.tr),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text('Удалить'.tr),
            ),
          ],
        ),
      ) ??
      false;
}

/// Header button: like every song of the playlist (and undo it right away).
class _LikeAllButton extends ConsumerWidget {
  const _LikeAllButton({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedKeysProvider);
    final all = tracks.isNotEmpty && tracks.every((t) => liked.contains(t.key));
    return HeaderIconButton(
      icon: all ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      tooltip: all ? 'Все треки в любимых'.tr : 'Лайкнуть все треки'.tr,
      onTap: () {
        if (tracks.isEmpty || all) return;
        final library = ref.read(libraryProvider);
        final fresh = [
          for (final t in tracks)
            if (!liked.contains(t.key)) t,
        ];
        library.likeMany(fresh, onTop: true);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'В любимых: +{0}'.trArgs([tracksLabel(fresh.length)]),
            ),
            action: SnackBarAction(
              label: 'Отменить'.tr,
              onPressed: () {
                for (final t in fresh) {
                  library.setLiked(t, false);
                }
              },
            ),
          ),
        );
      },
    );
  }
}
