import 'dart:io';

import '../widgets/content_width.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/catalog/taste.dart';
import '../../core/integrations/lastfm.dart';
import '../../core/library/backup.dart';
import '../../core/library/library.dart';
import '../../core/downloads/audio_cache.dart';
import '../../core/integrations/updater.dart';
import '../../core/integrations/updates.dart';
import '../../core/settings/settings.dart';
import '../theme/artwork_colors.dart';
import 'devices_screen.dart';
import 'playlist_screen.dart';
import '../theme/theme.dart';
import '../widgets/import_dialog.dart';
import '../widgets/library_import_sheet.dart';
import '../widgets/lights_panel.dart';
import '../widgets/living_backdrop.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/motion.dart';
import '../widgets/sound_panel.dart';
import '../widgets/wavy_progress.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Appearance settings with a live preview, in the spirit of Riff's theme
/// editor: accent, backdrop, font, sizes, and motion.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  static Route<void> route() => MaterialPageRoute(
    settings: const RouteSettings(name: routeName),
    builder: (_) => const SettingsScreen(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    void set(AppSettings Function(AppSettings) f) => notifier.update(f);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: WideScroll(
        max: 720,
        builder: (context, side) => ListView(
          padding: EdgeInsets.fromLTRB(16 + side, 0, 16 + side, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 6, 14),
                    child: Text(
                      'Настройки'.tr,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: notifier.reset,
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    color: SegueColors.textDim,
                  ),
                  label: Text(
                    'Сбросить'.tr,
                    style: TextStyle(color: SegueColors.textDim),
                  ),
                ),
              ],
            ),
            // Moved here from the sidebar: devices and bringing music in.
            _NavTile(
              icon: Icons.devices_rounded,
              title: 'Устройства'.tr,
              subtitle: 'Синхронизация, «Где играть», вход по коду'.tr,
              onTap: () => Navigator.of(context).push(DevicesScreen.route()),
            ),
            _NavTile(
              icon: Icons.link_rounded,
              title: 'Импорт плейлиста по ссылке'.tr,
              subtitle: 'Spotify, Яндекс Музыка, YouTube, SoundCloud'.tr,
              onTap: () async {
                final id = await showImportDialog(context);
                if (id != null && context.mounted) {
                  Navigator.of(context).push(PlaylistScreen.route(id));
                }
              },
            ),
            _NavTile(
              icon: Icons.move_down_rounded,
              title: 'Перенести всю библиотеку'.tr,
              subtitle: 'Все лайки и плейлисты из Яндекс Музыки или Spotify'.tr,
              onTap: () => showLibraryImport(context),
            ),
            _Section('Язык'.tr),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in {
                    'system': 'Как в системе'.tr,
                    ...L10n.languages,
                  }.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: s.language == e.key,
                      onSelected: (_) =>
                          set((x) => x.copyWith(language: e.key)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _Preview(),
            _Section('Звук'.tr),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const SoundPanel(),
            ),
            const SizedBox(height: 8),
            _Slider(
              title: 'Сведение треков'.tr,
              value: s.fadeSeconds,
              min: 0,
              max: 16,
              label: s.fadeSeconds < 0.5
                  ? 'выкл'.tr
                  : '{0} с'.trArgs([s.fadeSeconds.round()]),
              onChanged: (v) =>
                  set((x) => x.copyWith(fadeSeconds: v.roundToDouble())),
            ),
            _Tile(
              title: 'Подстраивать темп'.tr,
              subtitle: 'Как у диджея: следующая песня встаёт в темп и на сильную долю текущей, потом плавно возвращается к своему темпу'
                  .tr,
              trailing: Switch(
                value: s.matchTempo,
                onChanged: s.fadeSeconds < 1
                    ? null
                    : (v) => set((x) => x.copyWith(matchTempo: v)),
              ),
            ),
            _Tile(
              title: 'Пропускать вступления клипов'.tr,
              subtitle: 'Разговоры в начале и сценки в конце музыкальных видео (по данным SponsorBlock)'
                  .tr,
              trailing: Switch(
                value: s.skipIntros,
                onChanged: (v) => set((x) => x.copyWith(skipIntros: v)),
              ),
            ),
            _Tile(
              title: 'Выравнивать громкость'.tr,
              subtitle: 'Громкие и тихие треки звучат одинаково'.tr,
              trailing: Switch(
                value: s.normalizeVolume,
                onChanged: (v) => set((x) => x.copyWith(normalizeVolume: v)),
              ),
            ),
            const _CacheTile(),
            _Section('Свет'.tr),
            const LightsPanel(),
            _Section('Цвет акцента'.tr),
            _Tile(
              title: 'Брать из обложки'.tr,
              subtitle: 'Кнопки и прогресс окрашиваются под играющий трек'.tr,
              trailing: Switch(
                value: s.accentFromCover,
                onChanged: (v) => set((x) => x.copyWith(accentFromCover: v)),
              ),
            ),
            AnimatedOpacity(
              opacity: s.accentFromCover ? 0.35 : 1,
              duration: SegueMotion.medium,
              child: IgnorePointer(
                ignoring: s.accentFromCover,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final c in AppSettings.accents)
                        PressScale(
                          onTap: () => set((x) => x.copyWith(accent: c)),
                          child: AnimatedContainer(
                            duration: SegueMotion.medium,
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: s.accent == c
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _Section('Фон плеера'.tr),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SegmentedButton<BackdropStyle>(
                segments: [
                  ButtonSegment(
                    value: BackdropStyle.living,
                    label: Text('Живой'.tr),
                    icon: Icon(Icons.blur_on_rounded),
                  ),
                  ButtonSegment(
                    value: BackdropStyle.calm,
                    label: Text('Спокойный'.tr),
                    icon: Icon(Icons.water_rounded),
                  ),
                  ButtonSegment(
                    value: BackdropStyle.plain,
                    label: Text('Однотонный'.tr),
                    icon: Icon(Icons.square_rounded),
                  ),
                ],
                selected: {s.backdrop},
                onSelectionChanged: (v) =>
                    set((x) => x.copyWith(backdrop: v.first)),
              ),
            ),
            _Slider(
              title: 'Скорость движения'.tr,
              value: s.backdropSpeed,
              min: 0.2,
              max: 2.5,
              label: '×${s.backdropSpeed.toStringAsFixed(1)}',
              onChanged: (v) => set((x) => x.copyWith(backdropSpeed: v)),
            ),
            _Slider(
              title: 'Яркость цветов'.tr,
              value: s.backdropIntensity,
              min: 0.4,
              max: 1.4,
              label: '${(s.backdropIntensity * 100).round()}%',
              onChanged: (v) => set((x) => x.copyWith(backdropIntensity: v)),
            ),
            _Section('Шрифт'.tr),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in AppSettings.fonts)
                    PressScale(
                      onTap: () => set((x) => x.copyWith(font: f)),
                      child: AnimatedContainer(
                        duration: SegueMotion.medium,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: s.font == f
                              ? SegueColors.text
                              : SegueColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          f,
                          style: GoogleFonts.getFont(
                            f,
                            fontWeight: FontWeight.w700,
                            color: s.font == f
                                ? SegueColors.ink
                                : SegueColors.text,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _Section('Размеры'.tr),
            _Slider(
              title: 'Масштаб интерфейса'.tr,
              value: s.textScale,
              min: 0.85,
              max: 1.25,
              label: '${(s.textScale * 100).round()}%',
              onChanged: (v) => set((x) => x.copyWith(textScale: v)),
            ),
            _Slider(
              title: 'Текст песен'.tr,
              value: s.lyricsSize,
              min: 20,
              max: 38,
              label: '${s.lyricsSize.round()}',
              onChanged: (v) => set((x) => x.copyWith(lyricsSize: v)),
            ),
            _Section('Анимация текста'.tr),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
              ),
              child: LyricsPreview(settings: s),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SegmentedButton<LyricsStyle>(
                segments: [
                  ButtonSegment(
                    value: LyricsStyle.sweep,
                    label: Text('Заливка'.tr),
                  ),
                  ButtonSegment(
                    value: LyricsStyle.pop,
                    label: Text('По словам'.tr),
                  ),
                  ButtonSegment(
                    value: LyricsStyle.line,
                    label: Text('Строкой'.tr),
                  ),
                ],
                selected: {s.lyricsStyle},
                onSelectionChanged: (v) =>
                    set((x) => x.copyWith(lyricsStyle: v.first)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SegmentedButton<LyricsAlign>(
                segments: [
                  ButtonSegment(
                    value: LyricsAlign.left,
                    label: Text('Слева'.tr),
                    icon: Icon(Icons.format_align_left_rounded),
                  ),
                  ButtonSegment(
                    value: LyricsAlign.center,
                    label: Text('По центру'.tr),
                    icon: Icon(Icons.format_align_center_rounded),
                  ),
                ],
                selected: {s.lyricsAlign},
                onSelectionChanged: (v) =>
                    set((x) => x.copyWith(lyricsAlign: v.first)),
              ),
            ),
            _Slider(
              title: 'Свечение'.tr,
              value: s.lyricsGlow,
              min: 0,
              max: 1,
              label: '${(s.lyricsGlow * 100).round()}%',
              onChanged: (v) => set((x) => x.copyWith(lyricsGlow: v)),
            ),
            _Slider(
              title: 'Сдвиг текста'.tr,
              value: s.lyricsOffsetMs.toDouble(),
              min: -1500,
              max: 1500,
              label: '{0}{1} с'.trArgs([
                s.lyricsOffsetMs > 0 ? '+' : '',
                (s.lyricsOffsetMs / 1000).toStringAsFixed(1),
              ]),
              onChanged: (v) => set(
                (x) => x.copyWith(lyricsOffsetMs: (v / 100).round() * 100),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text(
                'Если текст отстаёт от песни — сдвинь вправо, если спешит — влево.'
                    .tr,
                style: TextStyle(color: SegueColors.textDim, fontSize: 12.5),
              ),
            ),
            _Tile(
              title: '3D-перспектива'.tr,
              subtitle:
                  'Обложка и текст развёрнуты к центру, строки уходят вглубь'
                      .tr,
              trailing: Switch(
                value: s.depth3d,
                onChanged: (v) => set((x) => x.copyWith(depth3d: v)),
              ),
            ),
            _Tile(
              title: 'Перевод текста'.tr,
              subtitle: 'Под каждой строкой — перевод на язык устройства'.tr,
              trailing: Switch(
                value: s.lyricsTranslate,
                onChanged: (v) => set((x) => x.copyWith(lyricsTranslate: v)),
              ),
            ),
            _Tile(
              title: 'Подъём слова'.tr,
              subtitle: 'Слово, которое поётся, слегка приподнимается'.tr,
              trailing: Switch(
                value: s.lyricsLift,
                onChanged: (v) => set((x) => x.copyWith(lyricsLift: v)),
              ),
            ),
            _Section('Эффекты'.tr),
            _Tile(
              title: 'Волна в прогрессе'.tr,
              subtitle: 'Полоска колышется во время игры'.tr,
              trailing: Switch(
                value: s.wavyProgress,
                onChanged: (v) => set((x) => x.copyWith(wavyProgress: v)),
              ),
            ),
            _Tile(
              title: 'Стекло'.tr,
              subtitle: 'Размытие под мини-плеером'.tr,
              trailing: Switch(
                value: s.glass,
                onChanged: (v) => set((x) => x.copyWith(glass: v)),
              ),
            ),
            if (Platform.isMacOS)
              _Tile(
                title: 'Виджет на рабочем столе'.tr,
                subtitle: 'Карточка с обложкой и кнопками под окнами. Её можно перетащить куда угодно'
                    .tr,
                trailing: Switch(
                  value: s.desktopWidget,
                  onChanged: (v) => set((x) => x.copyWith(desktopWidget: v)),
                ),
              ),
            if (Platform.isMacOS)
              _Tile(
                title: 'Живая чёлка'.tr,
                subtitle: 'На MacBook с вырезом: что играет — вокруг камеры, наведи мышь для кнопок'
                    .tr,
                trailing: Switch(
                  value: s.notchIsland,
                  onChanged: (v) => set((x) => x.copyWith(notchIsland: v)),
                ),
              ),
            _Tile(
              title: 'Меньше анимаций'.tr,
              subtitle:
                  'Фон замирает, списки появляются сразу. Бережёт батарею'.tr,
              trailing: Switch(
                value: s.reduceMotion,
                onChanged: (v) => set((x) => x.copyWith(reduceMotion: v)),
              ),
            ),
            _Section('Резервная копия'.tr),
            const _BackupTile(),
            const _Section('Last.fm'),
            const _LastFmTile(),
            _Section('Горячие клавиши'.tr),
            const _Hotkeys(),
            _Section('О приложении'.tr),
            const _About(),
          ],
        ),
      ),
    );
  }
}

/// Miniature player: backdrop, a lyric line, the wave and the play button,
/// all reacting to the settings as they change.
class _Preview extends ConsumerWidget {
  const _Preview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final colors = ref.watch(currentColorsProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 220,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LivingBackdrop(
              palette: colors.palette,
              base: colors.background,
              playing: true,
              speed: s.reduceMotion ? 0 : s.backdropSpeed,
              intensity: s.backdropIntensity,
              style: s.backdrop,
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'И музыка продолжится там,'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: s.lyricsSize * 0.8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'где ты остановился'.tr,
                    style: TextStyle(
                      fontSize: s.lyricsSize * 0.8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: WavyProgress(
                          progress: 0.42,
                          playing: s.wavyProgress,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: 16),
                      AnimatedContainer(
                        duration: SegueMotion.medium,
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.pause_rounded,
                          color: SegueColors.ink,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 26, 6, 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
        color: SegueColors.textDim,
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(color: SegueColors.textDim)),
    trailing: trailing,
  );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
    child: Row(
      children: [
        SizedBox(
          width: 170,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: const TextStyle(color: SegueColors.textDim),
          ),
        ),
      ],
    ),
  );
}

/// Last.fm account: sign in with your own API key, or sign out.
class _LastFmTile extends ConsumerWidget {
  const _LastFmTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastFm = ref.read(lastFmProvider);
    return ValueListenableBuilder<String?>(
      valueListenable: lastFm.user,
      builder: (context, user, _) => _Tile(
        title: user == null
            ? 'Скробблинг выключен'.tr
            : 'Вы вошли как {0}'.trArgs([user]),
        subtitle: user == null
            ? 'Отправлять прослушанное в профиль Last.fm'.tr
            : 'Каждый трек, дослушанный до половины, попадает в профиль'.tr,
        trailing: TextButton(
          onPressed: user == null
              ? () => showDialog<void>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => _LastFmDialog(lastFm),
                )
              : lastFm.signOut,
          child: Text(user == null ? 'Войти'.tr : 'Выйти'.tr),
        ),
      ),
    );
  }
}

class _LastFmDialog extends StatefulWidget {
  const _LastFmDialog(this.lastFm);
  final LastFm lastFm;

  @override
  State<_LastFmDialog> createState() => _LastFmDialogState();
}

class _LastFmDialogState extends State<_LastFmDialog> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_key, _secret, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.lastFm.signIn(
        apiKey: _key.text.trim(),
        secret: _secret.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Не получилось войти: проверь ключ, логин и пароль'.tr;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String hint, {bool hide = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            obscureText: hide,
            decoration: InputDecoration(hintText: hint),
          ),
        );
    return AlertDialog(
      backgroundColor: SegueColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Last.fm'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last.fm выдаёт ключи каждому приложению отдельно. Создай свой бесплатно и вставь сюда — пароль не сохраняется.'
                    .tr,
                style: TextStyle(color: SegueColors.textDim, fontSize: 13),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.last.fm/api/account/create'),
                ),
                child: Text('Получить ключ на last.fm'.tr),
              ),
              field(_key, 'API key'),
              field(_secret, 'Shared secret'),
              field(_user, 'Логин Last.fm'.tr),
              field(_pass, 'Пароль'.tr, hide: true),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'.tr),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Входим…'.tr : 'Войти'.tr),
        ),
      ],
    );
  }
}

class _Hotkeys extends StatelessWidget {
  const _Hotkeys();

  static List<(String, String)> get _keys => [
    ('Пробел'.tr, 'Пауза / играть'.tr),
    ('← →', 'Перемотка на 5 секунд'.tr),
    ('⌘/Ctrl + ← →', 'Предыдущий / следующий трек'.tr),
    ('⌘/Ctrl + ↑ ↓', 'Громкость'.tr),
    ('M', 'Выключить звук'.tr),
    ('L', 'В любимые'.tr),
    ('⌘/Ctrl + F', 'Поиск'.tr),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          for (final (key, what) in _keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(what)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider);
    final found = update.value;
    final updater = ref.read(updaterProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([
        updater.stage,
        updater.progress,
        updater.message,
      ]),
      builder: (context, _) {
        final stage = updater.stage.value;
        final p = updater.progress.value;
        final String subtitle;
        if (stage == UpdateStage.downloading) {
          subtitle = p == null
              ? updater.message.value
              : 'Скачиваем {0}… {1}%'.trArgs([
                  found?.version ?? '',
                  (p * 100).round(),
                ]);
        } else if (stage == UpdateStage.installing) {
          subtitle = 'Устанавливаем…'.tr;
        } else if (updater.message.value.isNotEmpty &&
            stage != UpdateStage.idle) {
          subtitle = updater.message.value;
        } else if (update.isLoading) {
          subtitle = 'Проверяем обновления…'.tr;
        } else if (found == null) {
          subtitle = 'У тебя последняя версия'.tr;
        } else if (updater.message.value.isNotEmpty) {
          subtitle = updater.message.value;
        } else {
          subtitle = 'Вышла версия {0}'.trArgs([found.version]);
        }
        final Widget trailing;
        if (updater.busy) {
          trailing = SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 3, value: p),
          );
        } else if (found == null) {
          trailing = TextButton(
            onPressed: () => ref.invalidate(updateProvider),
            child: Text('Проверить'.tr),
          );
        } else if (Updater.canInstall(found)) {
          trailing = FilledButton(
            onPressed: () => updater.install(found),
            child: Text('Обновить'.tr),
          );
        } else {
          trailing = FilledButton(
            onPressed: () => launchUrl(Uri.parse(found.url)),
            child: Text('Скачать'.tr),
          );
        }
        return _Tile(
          title: 'Segue $appVersion',
          subtitle: subtitle,
          trailing: trailing,
        );
      },
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: SegueColors.textDim),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );
}

/// "Сохранять недавние треки": switch, size, clear.
class _CacheTile extends ConsumerWidget {
  const _CacheTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final cache = ref.read(audioCacheProvider);
    return ValueListenableBuilder<int>(
      valueListenable: cache.bytes,
      builder: (context, bytes, _) {
        final mb = (bytes / (1024 * 1024)).round();
        return _Tile(
          title: 'Сохранять недавние треки'.tr,
          subtitle: 'До {0} последних треков хранятся на устройстве: запускаются сразу и играют без интернета. На телефоне — только по Wi-Fi.{1}'
              .trArgs([
                AudioCache.maxTracks,
                bytes > 0 ? ' Сейчас {0} МБ.'.trArgs([mb]) : '',
              ]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bytes > 0)
                IconButton(
                  tooltip: 'Очистить'.tr,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: cache.clear,
                ),
              Switch(
                value: s.offlineCache,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((x) => x.copyWith(offlineCache: v)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Saves the whole library to a file, or brings one back.
class _BackupTile extends ConsumerStatefulWidget {
  const _BackupTile();

  @override
  ConsumerState<_BackupTile> createState() => _BackupTileState();
}

class _BackupTileState extends ConsumerState<_BackupTile> {
  bool _busy = false;

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Сохранить резервную копию'.tr,
        fileName: Backup.fileName(DateTime.now()),
        bytes: Backup.encode(
          ref.read(libraryProvider),
          taste: ref.read(tasteProvider),
        ),
        mimeType: 'application/json',
      );
      if (saved != null && mounted) _say('Копия сохранена'.tr);
    } catch (e) {
      if (mounted) _say('Не получилось: {0}'.trArgs([e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Файл резервной копии'.tr,
      // Phones' file pickers often don't know .json: any file, checked below.
      type: Platform.isAndroid || Platform.isIOS
          ? FileType.any
          : FileType.custom,
      allowedExtensions: Platform.isAndroid || Platform.isIOS
          ? null
          : const ['json'],
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final backup = Backup.decode(await picked.first.readAsBytes());
      final s = Backup.restore(
        ref.read(libraryProvider),
        backup,
        taste: ref.read(tasteProvider),
      );
      if (mounted) {
        _say(
          'Восстановлено: {0}, {1}'.trArgs([
            '${s.liked} ${L10n.plural(s.liked, 'любимый трек|любимых трека|любимых треков')}',
            '${s.playlists} ${L10n.plural(s.playlists, 'плейлист|плейлиста|плейлистов')}',
          ]),
        );
      }
    } on FormatException {
      if (mounted) _say('Это не резервная копия Segue'.tr);
    } catch (e) {
      if (mounted) _say('Не получилось: {0}'.trArgs([e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Tile(
    title: 'Библиотека в файле'.tr,
    subtitle: 'Любимые, плейлисты, история и настройки. Восстановление добавляет их к тому, что уже есть'
        .tr,
    trailing: _busy
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Сохранить'.tr,
                icon: const Icon(Icons.save_alt_rounded),
                onPressed: _save,
              ),
              IconButton(
                tooltip: 'Восстановить'.tr,
                icon: const Icon(Icons.settings_backup_restore_rounded),
                onPressed: _restore,
              ),
            ],
          ),
  );
}
