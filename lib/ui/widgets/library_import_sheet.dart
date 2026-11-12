import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/import/import.dart';
import '../../core/import/library_import.dart';
import '../../core/import/playlist_importer.dart';
import '../../core/library/library.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Перенести всю библиотеку": all likes and playlists from Yandex Music or
/// Spotify at once.
Future<void> showLibraryImport(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SegueColors.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _LibraryImport(),
    );

class _LibraryImport extends ConsumerStatefulWidget {
  const _LibraryImport();

  @override
  ConsumerState<_LibraryImport> createState() => _LibraryImportState();
}

class _LibraryImportState extends ConsumerState<_LibraryImport> {
  final _login = TextEditingController();
  String? _step;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  LibraryImporter get _importer => LibraryImporter(ref.read(importerProvider));

  Future<void> _run(Future<ImportedLibrary> Function() load) async {
    setState(() {
      _step = 'Начинаем…'.tr;
      _error = null;
      _done = null;
    });
    try {
      final lib = await load();
      final store = ref.read(libraryProvider);
      final likes = store.likeMany(lib.liked);
      for (final p in lib.playlists) {
        final id = store.createPlaylist(p.name);
        store.addToPlaylist(id, p.tracks);
      }
      setState(
        () => _done = 'Готово: {0} {1} и {2} {3} из {4}. Треки находятся на YouTube, когда играют'
            .trArgs([
              likes,
              L10n.plural(likes, 'лайк|лайка|лайков'),
              lib.playlists.length,
              L10n.plural(
                lib.playlists.length,
                'плейлист|плейлиста|плейлистов',
              ),
              lib.service.tr,
            ]),
      );
    } on ImportException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Не получилось: {0}'.trArgs([e]));
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  Future<void> _pickSpotify() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Файлы экспорта Spotify'.tr,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'zip', 'json', 'txt'],
    );
    if (picked.isEmpty) return;
    await _run(() async {
      final files = [
        for (final f in picked) (name: f.name, bytes: await f.readAsBytes()),
      ];
      return _importer.files(files);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(currentColorsProvider).accent;
    final busy = _step != null;
    Widget card(String title, String sub, List<Widget> children) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: SegueColors.textDim)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Перенести всю библиотеку'.tr,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Все лайки и плейлисты разом. Уже лайкнутое не задвоится.'.tr,
              style: TextStyle(color: SegueColors.textDim),
            ),
            const SizedBox(height: 18),
            card(
              'Яндекс Музыка'.tr,
              'Логин или ссылка на профиль. Профиль должен быть открытым: Настройки → Приватность.'
                  .tr,
              [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _login,
                        enabled: !busy,
                        decoration: InputDecoration(
                          hintText: 'логин или music.yandex.ru/users/…'.tr,
                        ),
                        onSubmitted: (_) => _run(
                          () => _importer.yandex(
                            _login.text,
                            progress: (s) => setState(() => _step = s),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: SegueColors.ink,
                      ),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => _importer.yandex(
                                _login.text,
                                progress: (s) => setState(() => _step = s),
                              ),
                            ),
                      child: Text('Перенести'.tr),
                    ),
                  ],
                ),
              ],
            ),
            card(
              'Spotify',
              'Spotify не отдаёт лайки без входа, поэтому — файлами. Самое быстрое: exportify.app → войти → «Export All» и выбрать скачанный ZIP. Подойдут и данные из «Конфиденциальность → Скачать мои данные» (YourLibrary.json).'
                  .tr,
              [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: SegueColors.ink,
                      ),
                      onPressed: busy ? null : _pickSpotify,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text('Выбрать файлы'.tr),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri.parse('https://exportify.app')),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text('Открыть Exportify'.tr),
                    ),
                  ],
                ),
              ],
            ),
            if (_step != null)
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_step!)),
                ],
              ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
            if (_done != null)
              Text(
                _done!,
                style: const TextStyle(
                  color: Color(0xFF5BD68A),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
