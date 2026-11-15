import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/deezer.dart';
import '../../core/library/library.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

import 'package:segue/core/l10n/l10n.dart';

/// A ready-made playlist from the catalogue: listen, or keep a copy.
class MixScreen extends ConsumerWidget {
  const MixScreen({super.key, required this.mixId});

  final int mixId;

  static Route<void> route(int id) => MaterialPageRoute(
    settings: RouteSettings(name: '/mix/$id'),
    builder: (_) => MixScreen(mixId: id),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(mixPageProvider(mixId));
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
            'Не удалось загрузить подборку'.tr,
            style: const TextStyle(color: SegueColors.textDim),
          ),
        ),
        data: (p) {
          final (mix, tracks) = p;
          return TrackCollectionView(
            title: mix.title,
            subtitle: 'Подборка · {0}'.trArgs([tracksLabel(tracks.length)]),
            tracks: tracks,
            playContext: 'mix:$mixId',
            cover: Artwork(url: mix.cover, size: size, radius: 20),
            actions: [
              HeaderIconButton(
                icon: Icons.library_add_rounded,
                tooltip: 'Сохранить к себе'.tr,
                onTap: () {
                  final library = ref.read(libraryProvider);
                  final id = library.createPlaylist(mix.title);
                  library.addToPlaylist(id, tracks);
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Подборка «{0}» теперь в твоих плейлистах'.trArgs([
                          mix.title,
                        ]),
                      ),
                    ),
                  );
                },
              ),
              DownloadAllButton(tracks: tracks),
            ],
          );
        },
      ),
    );
  }
}
