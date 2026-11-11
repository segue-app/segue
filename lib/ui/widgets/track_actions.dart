import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/wave.dart';
import '../../core/downloads/downloads.dart';
import '../../core/library/library.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/player/trims.dart';
import '../theme/theme.dart';
import '../app_nav.dart';
import 'artwork.dart';
import 'motion.dart';
import 'trim_sheet.dart';

/// Heart that pops when toggled.
class LikeButton extends ConsumerWidget {
  const LikeButton({
    super.key,
    required this.track,
    required this.liked,
    this.size = 24,
  });

  final Track track;
  final bool liked;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PressScale(
      scale: 0.8,
      onTap: () => ref.read(libraryProvider).setLiked(track, !liked),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedSwitcher(
          duration: SegueMotion.medium,
          switchInCurve: SegueMotion.spring,
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(liked),
            size: size,
            color: liked ? const Color(0xFFFF6B81) : SegueColors.textDim,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with what you can do with a track.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  VoidCallback? onRemove,
}) {
  final library = ref.read(libraryProvider);
  final liked = library.isLiked(track);
  return showModalBottomSheet<void>(
    context: context,
    // Above the mini player and tab bar, not inside the tab.
    useRootNavigator: true,
    backgroundColor: SegueColors.surface,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Artwork(url: track.artworkUrl, size: 48, radius: 12),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: SegueColors.textDim),
              ),
            ),
            const Divider(color: SegueColors.line, height: 16),
            _Action(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: liked ? 'Убрать из любимых' : 'В любимые',
              onTap: () {
                library.setLiked(track, !liked);
                Navigator.pop(sheet);
              },
            ),
            if (track.source != SourceKind.local) ...[
              _Action(
                icon: Icons.person_rounded,
                label: 'Перейти к артисту',
                onTap: () {
                  Navigator.pop(sheet);
                  AppNav.artistByName(context, ref, track.artist);
                },
              ),
              _Action(
                icon: Icons.waves_rounded,
                label: 'Волна по треку',
                onTap: () {
                  Navigator.pop(sheet);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  ref.read(waveProvider).trackWave(track).catchError((
                    Object e,
                  ) {
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text('Не получилось запустить волну'),
                      ),
                    );
                  });
                },
              ),
            ],
            _Action(
              icon: Icons.playlist_play_rounded,
              label: 'Играть следующим',
              onTap: () {
                ref.read(playerProvider).addNext(track);
                Navigator.pop(sheet);
                _toast(context, 'Сыграет следующим');
              },
            ),
            _Action(
              icon: Icons.playlist_add_rounded,
              label: 'Добавить в плейлист',
              onTap: () {
                Navigator.pop(sheet);
                showAddToPlaylist(context, ref, [track]);
              },
            ),
            if (track.source != SourceKind.local)
              library.downloadedPath(track) == null
                  ? _Action(
                      icon: Icons.download_rounded,
                      label: 'Скачать',
                      onTap: () {
                        ref.read(downloadsProvider).download([track]);
                        Navigator.pop(sheet);
                        _toast(context, 'Скачиваем «${track.title}»');
                      },
                    )
                  : _Action(
                      icon: Icons.delete_outline_rounded,
                      label: 'Удалить с устройства',
                      onTap: () {
                        ref.read(downloadsProvider).delete(track);
                        Navigator.pop(sheet);
                      },
                    ),
            _Action(
              icon: Icons.content_cut_rounded,
              label: ref.read(trimStoreProvider).of(track) == null
                  ? 'Обрезать трек'
                  : 'Изменить обрезку',
              onTap: () {
                Navigator.pop(sheet);
                showTrimSheet(context, track);
              },
            ),
            if (onRemove != null)
              _Action(
                icon: Icons.remove_circle_outline_rounded,
                label: 'Убрать из плейлиста',
                onTap: () {
                  onRemove();
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Pick a playlist (or create one) and add [tracks] to it.
Future<void> showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the mini player and tab bar, not inside the tab.
    useRootNavigator: true,
    backgroundColor: SegueColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheet) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(playlistsProvider);
        final library = ref.read(libraryProvider);
        void addTo(String id, String name) {
          final added = library.addToPlaylist(id, tracks);
          Navigator.pop(sheet);
          _toast(
            context,
            added == 0 ? 'Уже есть в «$name»' : 'Добавлено в «$name»',
          );
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Добавить в плейлист',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                _Action(
                  icon: Icons.add_rounded,
                  label: 'Новый плейлист',
                  onTap: () async {
                    final name = await askPlaylistName(context);
                    if (name == null) return;
                    addTo(library.createPlaylist(name), name);
                  },
                ),
                for (final p in playlists)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Artwork(url: p.coverUrl, size: 44, radius: 10),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      tracksLabel(p.count),
                      style: const TextStyle(color: SegueColors.textDim),
                    ),
                    onTap: () => addTo(p.id, p.name),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Dialog for a new or renamed playlist; null when cancelled.
Future<String?> askPlaylistName(BuildContext context, {String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (dialog) => AlertDialog(
      backgroundColor: SegueColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(initial.isEmpty ? 'Новый плейлист' : 'Переименовать'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Название'),
        onSubmitted: (v) =>
            Navigator.pop(dialog, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.pop(dialog, v.isEmpty ? null : v);
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}

/// "1 трек", "3 трека", "5 треков".
String tracksLabel(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'трек'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
      ? 'трека'
      : 'треков';
  return '$n $word';
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: SegueColors.text),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
