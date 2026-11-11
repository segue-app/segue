import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/library/library.dart';
import '../theme/theme.dart';
import '../../core/downloads/downloads.dart';
import '../widgets/collection.dart';
import '../widgets/import_dialog.dart';
import '../widgets/motion.dart';
import '../widgets/nav.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'devices_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';

enum LibrarySection { liked, playlists, downloaded, local, history }

/// Which library section is open; the sidebar and home cards can set it.
final librarySectionProvider = StateProvider<LibrarySection>(
  (ref) => LibrarySection.liked,
);

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(librarySectionProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 12, 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Библиотека',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Настройки',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () => pushUnique(
                          Navigator.of(context),
                          SettingsScreen.route(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Устройства',
                        icon: const Icon(Icons.devices_rounded),
                        onPressed: () => pushUnique(
                          Navigator.of(context),
                          DevicesScreen.route(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final (s, label) in [
                        (LibrarySection.liked, 'Любимые'),
                        (LibrarySection.playlists, 'Плейлисты'),
                        (LibrarySection.downloaded, 'Скачанные'),
                        (LibrarySection.local, 'Мои файлы'),
                        (LibrarySection.history, 'История'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Tab(
                            label: label,
                            selected: s == section,
                            onTap: () =>
                                ref
                                        .read(librarySectionProvider.notifier)
                                        .state =
                                    s,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: SegueMotion.medium,
                    child: switch (section) {
                      LibrarySection.liked => const _Liked(
                        key: ValueKey('liked'),
                      ),
                      LibrarySection.playlists => const _Playlists(
                        key: ValueKey('pl'),
                      ),
                      LibrarySection.downloaded => const _Downloaded(
                        key: ValueKey('dl'),
                      ),
                      LibrarySection.local => const _LocalFiles(
                        key: ValueKey('local'),
                      ),
                      LibrarySection.history => const _History(
                        key: ValueKey('hist'),
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Downloaded extends ConsumerWidget {
  const _Downloaded({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(downloadedTracksProvider);
    final size = ref.read(libraryProvider).downloadsSize();
    return TrackCollectionView(
      title: 'Скачанные',
      subtitle:
          '${tracksLabel(tracks.length)} · ${(size / 1e6).toStringAsFixed(0)} МБ · играют без интернета',
      tracks: tracks,
      cover: const CoverCollage(
        urls: [],
        size: 150,
        icon: Icons.download_done_rounded,
        gradient: LinearGradient(
          colors: [Color(0xFF4FD1C5), Color(0xFF3B82F6)],
        ),
      ),
      emptyText:
          'Скачай трек через ••• → «Скачать», и он будет играть без интернета',
      onRemove: (t) => ref.read(downloadsProvider).delete(t),
      actions: [
        if (tracks.isNotEmpty)
          HeaderIconButton(
            icon: Icons.delete_sweep_rounded,
            onTap: () => ref.read(downloadsProvider).deleteAll(),
          ),
      ],
    );
  }
}

/// The user's own music folders.
class _LocalFiles extends ConsumerWidget {
  const _LocalFiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(localTracksProvider);
    final folders = ref.watch(foldersProvider);
    final local = ref.read(localLibraryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => local.addFolder(),
                icon: const Icon(Icons.create_new_folder_rounded),
                label: const Text('Добавить папку'),
              ),
              for (final f in folders)
                InputChip(
                  avatar: const Icon(Icons.folder_rounded, size: 18),
                  label: Text(f.split(RegExp(r'[\\/]')).last),
                  tooltip: f,
                  onDeleted: () => local.removeFolder(f),
                ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: local.scanning,
          builder: (context, scan, _) => scan == null
              ? const SizedBox()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Читаю теги и обложки… ${(scan.progress * 100).round()}%',
                        style: const TextStyle(color: SegueColors.textDim),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: scan.progress),
                    ],
                  ),
                ),
        ),
        Expanded(
          child: TrackCollectionView(
            title: 'Мои файлы',
            subtitle: folders.isEmpty
                ? 'MP3, FLAC, M4A, OGG, WAV с твоего устройства'
                : tracksLabel(tracks.length),
            tracks: tracks,
            cover: const CoverCollage(
              urls: [],
              size: 150,
              icon: Icons.folder_special_rounded,
              gradient: LinearGradient(
                colors: [Color(0xFFFFB547), Color(0xFFFF6B3D)],
              ),
            ),
            emptyText: 'Добавь папку с музыкой — треки появятся здесь вместе с обложками',
          ),
        ),
      ],
    );
  }
}

class _Liked extends ConsumerWidget {
  const _Liked({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(likedTracksProvider);
    return TrackCollectionView(
      title: 'Любимые треки',
      tracks: tracks,
      cover: const CoverCollage(
        urls: [],
        size: 150,
        icon: Icons.favorite_rounded,
        gradient: likedGradient,
      ),
      emptyText: 'Нажми ♡ у трека, и он появится здесь',
      actions: [DownloadAllButton(tracks: tracks)],
    );
  }
}

class _Playlists extends ConsumerWidget {
  const _Playlists({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      children: [
        _Row(
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.add_rounded, size: 28),
          ),
          title: 'Новый плейлист',
          onTap: () async {
            final name = await askPlaylistName(context);
            if (name == null || !context.mounted) return;
            final id = ref.read(libraryProvider).createPlaylist(name);
            pushUnique(Navigator.of(context), PlaylistScreen.route(id));
          },
        ),
        _Row(
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.download_rounded, size: 26),
          ),
          title: 'Импорт по ссылке',
          subtitle: 'Spotify, Яндекс Музыка, YouTube, SoundCloud',
          onTap: () async {
            final id = await showImportDialog(context);
            if (id != null && context.mounted) {
              pushUnique(Navigator.of(context), PlaylistScreen.route(id));
            }
          },
        ),
        for (final (i, p) in playlists.indexed)
          StaggeredEntrance(
            index: i % 12,
            child: _Row(
              leading: CoverCollage(urls: [p.coverUrl], size: 56, radius: 16),
              title: p.name,
              subtitle: tracksLabel(p.count),
              onTap: () =>
                  pushUnique(Navigator.of(context), PlaylistScreen.route(p.id)),
            ),
          ),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  const _History({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(recentlyPlayedProvider);
    if (tracks.isEmpty) {
      return const Center(
        child: Text(
          'Здесь появится то, что ты слушал',
          style: TextStyle(color: SegueColors.textDim),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      itemCount: tracks.length + 1,
      itemBuilder: (context, i) {
        if (i == tracks.length) {
          return Center(
            child: TextButton.icon(
              onPressed: () => ref.read(libraryProvider).clearHistory(),
              icon: const Icon(
                Icons.delete_sweep_rounded,
                color: SegueColors.textDim,
              ),
              label: const Text(
                'Очистить историю',
                style: TextStyle(color: SegueColors.textDim),
              ),
            ),
          );
        }
        return StaggeredEntrance(
          index: i % 12,
          child: TrackTile(tracks: tracks, index: i),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: 0.98,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: SegueColors.textDim,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: SegueColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SegueMotion.medium,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? SegueColors.text : SegueColors.surfaceHigh,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? SegueColors.ink : SegueColors.textDim,
          ),
        ),
      ),
    );
  }
}
