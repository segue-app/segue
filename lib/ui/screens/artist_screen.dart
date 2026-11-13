import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/deezer.dart';
import '../../core/catalog/wave.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/motion.dart';
import '../widgets/nav.dart';
import '../widgets/track_tile.dart';
import 'album_screen.dart';

import 'package:segue/core/l10n/l10n.dart';

import '../widgets/collection.dart';
import '../widgets/track_actions.dart';

/// Artist: photo, play / wave, popular tracks, releases, similar artists.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistId});

  final int artistId;

  static Route<void> route(int id) => MaterialPageRoute(
    settings: RouteSettings(name: '/artist/$id'),
    builder: (_) => ArtistScreen(artistId: id),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(artistPageProvider(artistId));
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
            'Не удалось загрузить артиста'.tr,
            style: TextStyle(color: SegueColors.textDim),
          ),
        ),
        data: (p) => _Body(page: p),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.page});

  final ArtistPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = page.artist;
    final accent = ref.watch(currentColorsProvider).accent;
    final top = page.top;
    final wide = MediaQuery.sizeOf(context).width > 600;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: wide
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: Artwork(url: a.picture, size: wide ? 200 : 170, radius: 0),
          ),
          SizedBox(width: wide ? 28 : 0, height: wide ? 0 : 16),
          Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a.name,
                textAlign: wide ? TextAlign.start : TextAlign.center,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                ),
              ),
              if (a.fans > 0)
                Text(
                  _fans(a.fans),
                  style: const TextStyle(
                    color: SegueColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Pill(
                    icon: Icons.play_arrow_rounded,
                    label: 'Слушать'.tr,
                    color: accent,
                    filled: true,
                    onTap: top.isEmpty
                        ? null
                        : () => ref.read(playerProvider).playList(top, 0),
                  ),
                  _Pill(
                    icon: Icons.waves_rounded,
                    label: 'Волна артиста'.tr,
                    color: accent,
                    onTap: () => ref.read(waveProvider).artistWave(a),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: header,
            ),
          ),
        ),
        if (top.isNotEmpty) _Title('Популярные треки'.tr),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < top.length && i < 10; i++)
                      StaggeredEntrance(
                        index: i,
                        child: TrackTile(tracks: top, index: i),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          ArtistTracksScreen.route(a.id, a.name, a.picture),
                        ),
                        icon: const Icon(Icons.queue_music_rounded),
                        label: Text('Все треки'.tr),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (page.albums.isNotEmpty) ...[
          _Title('Релизы'.tr),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: page.albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final al = page.albums[i];
                  return PressScale(
                    onTap: () => pushUnique(
                      Navigator.of(context),
                      AlbumScreen.route(al.id),
                    ),
                    child: SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Artwork(url: al.cover, size: 150, radius: 18),
                          const SizedBox(height: 8),
                          Text(
                            al.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            [
                              if (al.year != null) '${al.year}',
                              _type(al.type),
                            ].join(' · '),
                            style: const TextStyle(
                              color: SegueColors.textDim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        if (page.related.isNotEmpty) ...[
          _Title('Похожие исполнители'.tr),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: page.related.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final r = page.related[i];
                  return PressScale(
                    onTap: () => pushUnique(
                      Navigator.of(context),
                      ArtistScreen.route(r.id),
                    ),
                    child: SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          ClipOval(
                            child: Artwork(
                              url: r.picture,
                              size: 120,
                              radius: 0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  static String _fans(int n) {
    if (n >= 1000000) {
      return '{0} млн слушателей'.trArgs([(n / 1e6).toStringAsFixed(1)]);
    }
    if (n >= 1000) return '{0} тыс. слушателей'.trArgs([(n / 1000).round()]);
    return '{0} слушателей'.trArgs([n]);
  }

  static String _type(String? t) => switch (t) {
    'single' => 'Сингл'.tr,
    'ep' => 'EP',
    'compile' => 'Сборник'.tr,
    _ => 'Альбом'.tr,
  };
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
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
    return PressScale(
      onTap: onTap,
      child: Container(
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
    );
  }
}

/// All of an artist's songs, popular first, then by release.
class ArtistTracksScreen extends ConsumerWidget {
  const ArtistTracksScreen({
    super.key,
    required this.artistId,
    required this.name,
    this.picture,
  });

  final int artistId;
  final String name;
  final String? picture;

  static Route<void> route(int id, String name, String? picture) =>
      MaterialPageRoute(
        settings: RouteSettings(name: '/artist/$id/tracks'),
        builder: (_) =>
            ArtistTracksScreen(artistId: id, name: name, picture: picture),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(artistAllTracksProvider(artistId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Не удалось загрузить артиста'.tr,
            style: TextStyle(color: SegueColors.textDim),
          ),
        ),
        data: (tracks) => TrackCollectionView(
          title: name,
          subtitle: tracksLabel(tracks.length),
          tracks: tracks,
          playContext: 'artist:$artistId',
          cover: CoverCollage(
            urls: [picture],
            size: MediaQuery.sizeOf(context).width > 600 ? 200.0 : 180.0,
          ),
        ),
      ),
    );
  }
}
