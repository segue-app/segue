import 'dart:io';

import '../widgets/content_width.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/library/library.dart';
import '../../core/models/track.dart';
import '../theme/theme.dart';
import '../../core/downloads/downloads.dart';
import '../widgets/collection.dart';
import '../widgets/confirm.dart';
import '../widgets/import_dialog.dart';
import '../widgets/motion.dart';
import '../widgets/nav.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'devices_screen.dart';
import 'album_screen.dart';
import 'playlist_screen.dart';
import '../widgets/artwork.dart';
import 'settings_screen.dart';

import 'package:segue/core/l10n/l10n.dart';

import '../widgets/shared_playlist_sheet.dart';
import '../widgets/h_scroll.dart';

enum LibrarySection { liked, playlists, albums, downloaded, local, history }

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
        child: ContentWidth(
          max: 820,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContentBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 12, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Библиотека'.tr,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Настройки'.tr,
                            icon: const Icon(Icons.tune_rounded),
                            onPressed: () => pushUnique(
                              Navigator.of(context),
                              SettingsScreen.route(),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Устройства'.tr,
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
                      child: HScroll(
                        builder: (context, c) => ListView(
                          scrollDirection: Axis.horizontal,
                          controller: c,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final (s, label) in [
                              (LibrarySection.liked, 'Любимые'.tr),
                              (LibrarySection.playlists, 'Плейлисты'.tr),
                              (LibrarySection.albums, 'Альбомы'.tr),
                              (LibrarySection.downloaded, 'Скачанные'.tr),
                              (LibrarySection.local, 'Мои файлы'.tr),
                              (LibrarySection.history, 'История'.tr),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Tab(
                                  label: label,
                                  selected: s == section,
                                  onTap: () =>
                                      ref
                                              .read(
                                                librarySectionProvider.notifier,
                                              )
                                              .state =
                                          s,
                                ),
                              ),
                          ],
                        ),
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
                    LibrarySection.albums => const _Albums(
                      key: ValueKey('albums'),
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
      title: 'Скачанные'.tr,
      subtitle: '{0} · {1} МБ · играют без интернета'.trArgs([
        tracksLabel(tracks.length),
        (size / 1e6).toStringAsFixed(0),
      ]),
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
          'Скачай трек через ••• → «Скачать», и он будет играть без интернета'
              .tr,
      onRemove: (t) async {
        final ok = await confirmDialog(
          context,
          title: 'Удалить «{0}» из скачанных?'.trArgs([t.displayTitle]),
          message: 'Файл удалится с устройства. Трек останется в библиотеке и будет играть из интернета.'
              .tr,
        );
        if (ok) await ref.read(downloadsProvider).delete(t);
      },
      actions: [
        // Phones keep the files inside the app, where no file manager
        // reaches; a computer can show the folder.
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
          HeaderIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: 'Показать папку'.tr,
            onTap: () async {
              final dir = await ref.read(downloadsProvider).folder();
              await dir.create(recursive: true);
              await launchUrl(Uri.directory(dir.path));
            },
          ),
        if (tracks.isNotEmpty)
          HeaderIconButton(
            icon: Icons.delete_sweep_rounded,
            tooltip: 'Удалить все скачанные'.tr,
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: 'Удалить все скачанные?'.tr,
                message: '{0} · {1} МБ освободится на устройстве. Треки останутся в библиотеке.'
                    .trArgs([
                      tracksLabel(tracks.length),
                      (size / 1e6).toStringAsFixed(0),
                    ]),
                action: 'Удалить все'.tr,
              );
              if (ok) await ref.read(downloadsProvider).deleteAll();
            },
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
        ContentBox(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => local.addFolder(),
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: Text('Добавить папку'.tr),
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
                        'Читаю теги и обложки… {0}%'.trArgs([
                          (scan.progress * 100).round(),
                        ]),
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
            title: 'Мои файлы'.tr,
            subtitle: folders.isEmpty
                ? 'MP3, FLAC, M4A, OGG, WAV с твоего устройства'.tr
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
            emptyText: 'Добавь папку с музыкой — треки появятся здесь вместе с обложками'
                .tr,
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
      title: 'Любимые треки'.tr,
      tracks: tracks,
      cover: const CoverCollage(
        urls: [],
        size: 150,
        icon: Icons.favorite_rounded,
        gradient: likedGradient,
      ),
      emptyText: 'Нажми ♡ у трека, и он появится здесь'.tr,
      playContext: 'liked',
      onReorder: (from, to) =>
          ref.read(libraryProvider).moveLiked(tracks, from, to),
      actions: [DownloadAllButton(tracks: tracks)],
    );
  }
}

/// Albums added with ♥ on their page: covers in a grid.
class _Albums extends ConsumerWidget {
  const _Albums({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(savedAlbumsProvider);
    if (albums.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.album_rounded,
                size: 48,
                color: SegueColors.textDim,
              ),
              const SizedBox(height: 12),
              Text(
                'Здесь будут твои альбомы'.tr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Открой альбом и нажми ♥ рядом с «Слушать»'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: SegueColors.textDim),
              ),
            ],
          ),
        ),
      );
    }
    return WideScroll(
      builder: (context, side) => GridView.builder(
        padding: EdgeInsets.fromLTRB(16 + side, 4, 16 + side, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.74,
        ),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final al = albums[i];
          return PressScale(
            onTap: () =>
                pushUnique(Navigator.of(context), AlbumScreen.route(al.id)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, c) =>
                        Artwork(url: al.cover, size: c.maxWidth, radius: 18),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  al.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  [al.artist, if (al.year != null) '${al.year}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SegueColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Playlists extends ConsumerWidget {
  const _Playlists({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return WideScroll(
      builder: (context, side) => ListView(
        padding: EdgeInsets.fromLTRB(8 + side, 4, 8 + side, 16),
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
            title: 'Новый плейлист'.tr,
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
            title: 'Импорт по ссылке'.tr,
            subtitle: 'Spotify, Яндекс Музыка, Apple Music, Deezer, YouTube, SoundCloud'
                .tr,
            onTap: () async {
              final id = await showImportDialog(context);
              if (id != null && context.mounted) {
                pushUnique(Navigator.of(context), PlaylistScreen.route(id));
              }
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
              child: const Icon(Icons.group_rounded, size: 26),
            ),
            title: 'Плейлист друга'.tr,
            subtitle: 'Присоединиться по коду'.tr,
            onTap: () async {
              final id = await askJoinSharedPlaylist(context, ref);
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
                onTap: () => pushUnique(
                  Navigator.of(context),
                  PlaylistScreen.route(p.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Everything listened to, as in Yandex Music: by day (today, yesterday,
/// a date), searchable, each song removable, the whole of it clearable.
class _History extends ConsumerStatefulWidget {
  const _History({super.key});

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // The last result, reused until the history or the query changes: up to
  // a thousand songs were lowercased and regrouped on every rebuild.
  List<(Track, DateTime)>? _memoAll;
  List<String> _hay = const [];
  String? _memoQ;
  late (List<(Track, DateTime)>, List<Track>, List<Object>) _memo;

  (List<(Track, DateTime)>, List<Track>, List<Object>) _rowsFor(
    List<(Track, DateTime)> all,
    String q,
  ) {
    if (identical(all, _memoAll) && q == _memoQ) return _memo;
    if (!identical(all, _memoAll)) {
      _hay = [
        for (final e in all) '${e.$1.title} ${e.$1.artist}'.toLowerCase(),
      ];
    }
    _memoAll = all;
    _memoQ = q;
    final words = q.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (words.every(_hay[i].contains)) all[i],
    ];
    final tracks = [for (final e in shown) e.$1];
    // Rows: a day's title, then its songs.
    final rows = <Object>[];
    String? last;
    for (var i = 0; i < shown.length; i++) {
      final d = _day(shown[i].$2);
      if (d != last) rows.add(d);
      last = d;
      rows.add(i);
    }
    return _memo = (shown, tracks, rows);
  }

  static String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Сегодня'.tr;
    if (diff == 1) return 'Вчера'.tr;
    final months = 'января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря'
        .tr
        .split('|');
    final m = months.length == 12 ? months[d.month - 1] : '${d.month}';
    return d.year == now.year ? '${d.day} $m' : '${d.day} $m ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(listeningHistoryProvider);
    final library = ref.read(libraryProvider);
    if (all.isEmpty) {
      return Center(
        child: Text(
          'Здесь появится то, что ты слушал'.tr,
          style: const TextStyle(color: SegueColors.textDim),
        ),
      );
    }
    final (shown, tracks, rows) = _rowsFor(all, _q);
    return WideScroll(
      builder: (context, side) => ListView.builder(
        padding: EdgeInsets.fromLTRB(8 + side, 4, 8 + side, 16),
        itemCount: rows.length + 2,
        itemBuilder: (context, r) {
          if (r == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Поиск в истории'.tr,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            );
          }
          if (r == rows.length + 1) {
            return Center(
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    title: 'Очистить историю?'.tr,
                    message: 'Все прослушанные треки пропадут из истории на этом устройстве.'
                        .tr,
                    action: 'Очистить'.tr,
                  );
                  if (ok) library.clearHistory();
                },
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                  color: SegueColors.textDim,
                ),
                label: Text(
                  'Очистить историю'.tr,
                  style: const TextStyle(color: SegueColors.textDim),
                ),
              ),
            );
          }
          final row = rows[r - 1];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
              child: Text(
                row,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }
          final i = row as int;
          return Row(
            children: [
              Expanded(
                child: TrackTile(
                  key: ValueKey(tracks[i].key),
                  tracks: tracks,
                  index: i,
                ),
              ),
              IconButton(
                tooltip: 'Убрать из истории'.tr,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: SegueColors.textDim,
                onPressed: () => library.removeFromHistory(tracks[i]),
              ),
            ],
          );
        },
      ),
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
