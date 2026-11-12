import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/deezer.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

import 'package:segue/core/l10n/l10n.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.albumId});

  final int albumId;

  static Route<void> route(int id) => MaterialPageRoute(
    settings: RouteSettings(name: '/album/$id'),
    builder: (_) => AlbumScreen(albumId: id),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(albumPageProvider(albumId));
    final size = MediaQuery.sizeOf(context).width > 600 ? 200.0 : 180.0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Не удалось загрузить альбом'.tr,
            style: TextStyle(color: SegueColors.textDim),
          ),
        ),
        data: (p) {
          final (album, tracks) = p;
          return TrackCollectionView(
            title: album.title,
            subtitle: [
              album.artist,
              if (album.year != null) '${album.year}',
              tracksLabel(tracks.length),
            ].join(' · '),
            tracks: tracks,
            cover: Artwork(url: album.cover, size: size, radius: 20),
            actions: [
              DownloadAllButton(tracks: tracks),
              HeaderIconButton(
                icon: Icons.playlist_add_rounded,
                onTap: () => showAddToPlaylist(context, ref, tracks),
              ),
            ],
          );
        },
      ),
    );
  }
}
