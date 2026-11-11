import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

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
              emptyText: 'Добавляй треки через ••• → «Добавить в плейлист»',
              onRemove: (t) => library.removeFromPlaylist(playlistId, t),
              actions: [
                DownloadAllButton(tracks: tracks),
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
          title: Text('Удалить «$name»?'),
          content: const Text('Треки останутся в поиске и в любимых.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ) ??
      false;
}
