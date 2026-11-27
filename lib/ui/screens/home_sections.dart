part of 'home_screen.dart';

/// "Продолжить": the song listening stopped at (after the app was
/// closed), from that very moment, with the queue it was in.
class _Continue extends ConsumerWidget {
  const _Continue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Something is loaded already: the player bar shows it.
    if (ref.watch(currentTrackProvider).value != null) {
      return const SizedBox.shrink();
    }
    final point = ref.read(resumeProvider);
    final r = point.load();
    if (r == null) return const SizedBox.shrink();
    final t = r.track;
    final s = r.position.inSeconds;
    final at = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    final from = r.wave?.tr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: PressScale(
        scale: 0.98,
        onTap: () async {
          await point.resume(r.snap);
          if (r.wave == Wave.myWaveTitle) {
            ref
                .read(waveProvider)
                .continueMyWave(ref.read(waveSettingsProvider));
          }
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Artwork(url: t.artworkUrl, size: 56, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Продолжить'.tr,
                      style: const TextStyle(
                        color: SegueColors.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        t.artist,
                        'с {0}'.trArgs([at]),
                        ?from,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SegueColors.textDim,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: SegueColors.text,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 28,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Новинки твоих исполнителей": their albums and singles of the last
/// two months.
class _NewReleases extends ConsumerWidget {
  const _NewReleases();

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(newReleasesProvider).value ?? const <Album>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Новинки твоих исполнителей'.tr),
        SizedBox(
          height: 206,
          child: HScroll(
            builder: (context, c) => ListView.separated(
              scrollDirection: Axis.horizontal,
              controller: c,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final a = list[i];
                final kind = switch (a.type) {
                  'single' => 'Сингл'.tr,
                  'ep' => 'EP',
                  _ => 'Альбом'.tr,
                };
                return StaggeredEntrance(
                  index: i % 8,
                  child: PressScale(
                    onTap: () => pushUnique(
                      Navigator.of(context),
                      AlbumScreen.route(a.id),
                    ),
                    child: SizedBox(
                      width: 148,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Artwork(url: a.cover, size: 148, radius: 20),
                          const SizedBox(height: 10),
                          Text(
                            a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${a.artist} · $kind · ${_date(a.released!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SegueColors.textDim,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// "Твои исполнители": round photos of the artists you listen to most.
/// Deezer's page for those it knows, a radio of your song for the rest.
class _YourArtists extends ConsumerWidget {
  const _YourArtists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(favouriteArtistsProvider).value ?? const [];
    if (list.length < 3) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Твои исполнители'.tr),
        SizedBox(
          height: 140,
          child: HScroll(
            builder: (context, c) => ListView.separated(
              scrollDirection: Axis.horizontal,
              controller: c,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final a = list[i];
                return StaggeredEntrance(
                  index: i % 8,
                  child: PressScale(
                    onTap: () {
                      final dz = a.deezer;
                      if (dz != null) {
                        pushUnique(
                          Navigator.of(context),
                          ArtistScreen.route(dz.id),
                        );
                        return;
                      }
                      ref.read(waveProvider).trackWave(a.latest).catchError((
                        Object e,
                      ) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$e')),
                          );
                        }
                      });
                    },
                    child: SizedBox(
                      width: 104,
                      child: Column(
                        children: [
                          Artwork(url: a.picture, size: 104, radius: 52),
                          const SizedBox(height: 8),
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
