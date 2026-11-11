import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/import/import.dart';
import '../../core/import/playlist_importer.dart';
import '../../core/library/library.dart';
import '../theme/theme.dart';
import 'track_actions.dart';

/// Paste a playlist link from Spotify, Yandex Music, YouTube or SoundCloud;
/// creates a Segue playlist and returns its id (null if cancelled).
Future<String?> showImportDialog(BuildContext context) => showDialog<String>(
  context: context,
  useRootNavigator: true,
  builder: (_) => const _ImportDialog(),
);

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pasteIfLink();
  }

  /// If the clipboard already holds a supported link, fill it in.
  Future<void> _pasteIfLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null &&
        PlaylistImporter.serviceOf(text) != null &&
        mounted &&
        _controller.text.isEmpty) {
      setState(() => _controller.text = text);
    }
  }

  Future<void> _import() async {
    final link = _controller.text.trim();
    if (link.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final playlist = await ref.read(importerProvider).import(link);
      if (playlist.tracks.isEmpty) {
        throw ImportException('В плейлисте нет доступных треков');
      }
      final library = ref.read(libraryProvider);
      final id = library.createPlaylist(playlist.name);
      library.addToPlaylist(id, playlist.tracks);
      if (!mounted) return;
      Navigator.pop(context, id);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '«${playlist.name}»: ${tracksLabel(playlist.tracks.length)} из ${playlist.service}',
          ),
        ),
      );
    } on ImportException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
        () => _error =
            'Не получилось загрузить плейлист. Проверь ссылку и интернет',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = PlaylistImporter.serviceOf(_controller.text);
    return AlertDialog(
      backgroundColor: SegueColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Text(
        'Импорт плейлиста',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Вставь ссылку на публичный плейлист или альбом.',
              style: TextStyle(color: SegueColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in [
                  'Spotify',
                  'Яндекс Музыка',
                  'YouTube',
                  'SoundCloud',
                ])
                  AnimatedContainer(
                    duration: SegueMotion.medium,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: s == service
                          ? SegueColors.accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: s == service
                            ? SegueColors.accent
                            : SegueColors.textDim,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _import(),
              decoration: const InputDecoration(
                hintText: 'https://open.spotify.com/playlist/…',
                prefixIcon: Icon(
                  Icons.link_rounded,
                  color: SegueColors.textDim,
                ),
              ),
            ),
            AnimatedSize(
              duration: SegueMotion.medium,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                    ),
            ),
            if (service == 'Spotify' || service == 'Яндекс Музыка')
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Звук для каждого трека найдётся на YouTube, когда он заиграет.',
                  style: TextStyle(color: SegueColors.textDim, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy || service == null ? null : _import,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Импортировать'),
        ),
      ],
    );
  }
}
