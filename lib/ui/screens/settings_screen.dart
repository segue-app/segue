import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/integrations/lastfm.dart';
import '../../core/integrations/updates.dart';
import '../../core/settings/settings.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/living_backdrop.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/motion.dart';
import '../widgets/sound_panel.dart';
import '../widgets/wavy_progress.dart';

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(6, 0, 6, 14),
                      child: Text(
                        'Настройки',
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
                    label: const Text(
                      'Сбросить',
                      style: TextStyle(color: SegueColors.textDim),
                    ),
                  ),
                ],
              ),
              const _Preview(),
              const _Section('Звук'),
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
                title: 'Плавные переходы',
                value: s.fadeSeconds,
                min: 0,
                max: 8,
                label: s.fadeSeconds < 0.5
                    ? 'выкл'
                    : '${s.fadeSeconds.round()} с',
                onChanged: (v) =>
                    set((x) => x.copyWith(fadeSeconds: v.roundToDouble())),
              ),
              const _Section('Цвет акцента'),
              _Tile(
                title: 'Брать из обложки',
                subtitle: 'Кнопки и прогресс окрашиваются под играющий трек',
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
              const _Section('Фон плеера'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: SegmentedButton<BackdropStyle>(
                  segments: const [
                    ButtonSegment(
                      value: BackdropStyle.living,
                      label: Text('Живой'),
                      icon: Icon(Icons.blur_on_rounded),
                    ),
                    ButtonSegment(
                      value: BackdropStyle.calm,
                      label: Text('Спокойный'),
                      icon: Icon(Icons.water_rounded),
                    ),
                    ButtonSegment(
                      value: BackdropStyle.plain,
                      label: Text('Однотонный'),
                      icon: Icon(Icons.square_rounded),
                    ),
                  ],
                  selected: {s.backdrop},
                  onSelectionChanged: (v) =>
                      set((x) => x.copyWith(backdrop: v.first)),
                ),
              ),
              _Slider(
                title: 'Скорость движения',
                value: s.backdropSpeed,
                min: 0.2,
                max: 2.5,
                label: '×${s.backdropSpeed.toStringAsFixed(1)}',
                onChanged: (v) => set((x) => x.copyWith(backdropSpeed: v)),
              ),
              _Slider(
                title: 'Яркость цветов',
                value: s.backdropIntensity,
                min: 0.4,
                max: 1.4,
                label: '${(s.backdropIntensity * 100).round()}%',
                onChanged: (v) => set((x) => x.copyWith(backdropIntensity: v)),
              ),
              const _Section('Шрифт'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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
              const _Section('Размеры'),
              _Slider(
                title: 'Масштаб интерфейса',
                value: s.textScale,
                min: 0.85,
                max: 1.25,
                label: '${(s.textScale * 100).round()}%',
                onChanged: (v) => set((x) => x.copyWith(textScale: v)),
              ),
              _Slider(
                title: 'Текст песен',
                value: s.lyricsSize,
                min: 20,
                max: 38,
                label: '${s.lyricsSize.round()}',
                onChanged: (v) => set((x) => x.copyWith(lyricsSize: v)),
              ),
              const _Section('Анимация текста'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: LyricsPreview(settings: s),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: SegmentedButton<LyricsStyle>(
                  segments: const [
                    ButtonSegment(
                      value: LyricsStyle.sweep,
                      label: Text('Заливка'),
                    ),
                    ButtonSegment(
                      value: LyricsStyle.pop,
                      label: Text('По словам'),
                    ),
                    ButtonSegment(
                      value: LyricsStyle.line,
                      label: Text('Строкой'),
                    ),
                  ],
                  selected: {s.lyricsStyle},
                  onSelectionChanged: (v) =>
                      set((x) => x.copyWith(lyricsStyle: v.first)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SegmentedButton<LyricsAlign>(
                  segments: const [
                    ButtonSegment(
                      value: LyricsAlign.left,
                      label: Text('Слева'),
                      icon: Icon(Icons.format_align_left_rounded),
                    ),
                    ButtonSegment(
                      value: LyricsAlign.center,
                      label: Text('По центру'),
                      icon: Icon(Icons.format_align_center_rounded),
                    ),
                  ],
                  selected: {s.lyricsAlign},
                  onSelectionChanged: (v) =>
                      set((x) => x.copyWith(lyricsAlign: v.first)),
                ),
              ),
              _Slider(
                title: 'Свечение',
                value: s.lyricsGlow,
                min: 0,
                max: 1,
                label: '${(s.lyricsGlow * 100).round()}%',
                onChanged: (v) => set((x) => x.copyWith(lyricsGlow: v)),
              ),
              _Slider(
                title: 'Сдвиг текста',
                value: s.lyricsOffsetMs.toDouble(),
                min: -1500,
                max: 1500,
                label:
                    '${s.lyricsOffsetMs > 0 ? '+' : ''}${(s.lyricsOffsetMs / 1000).toStringAsFixed(1)} с',
                onChanged: (v) => set(
                  (x) => x.copyWith(lyricsOffsetMs: (v / 100).round() * 100),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Text(
                  'Если текст отстаёт от песни — сдвинь вправо, если спешит — влево.',
                  style: TextStyle(color: SegueColors.textDim, fontSize: 12.5),
                ),
              ),
              _Tile(
                title: 'Размытие соседних строк',
                subtitle: 'Текущая строка в фокусе, остальные мягко размыты',
                trailing: Switch(
                  value: s.lyricsBlur,
                  onChanged: (v) => set((x) => x.copyWith(lyricsBlur: v)),
                ),
              ),
              _Tile(
                title: '3D-перспектива',
                subtitle:
                    'Обложка и текст развёрнуты к центру, строки уходят вглубь',
                trailing: Switch(
                  value: s.depth3d,
                  onChanged: (v) => set((x) => x.copyWith(depth3d: v)),
                ),
              ),
              _Tile(
                title: 'Перевод текста',
                subtitle: 'Под каждой строкой — перевод на язык устройства',
                trailing: Switch(
                  value: s.lyricsTranslate,
                  onChanged: (v) => set((x) => x.copyWith(lyricsTranslate: v)),
                ),
              ),
              _Tile(
                title: 'Подъём слова',
                subtitle: 'Слово, которое поётся, слегка приподнимается',
                trailing: Switch(
                  value: s.lyricsLift,
                  onChanged: (v) => set((x) => x.copyWith(lyricsLift: v)),
                ),
              ),
              const _Section('Эффекты'),
              _Tile(
                title: 'Волна в прогрессе',
                subtitle: 'Полоска колышется во время игры',
                trailing: Switch(
                  value: s.wavyProgress,
                  onChanged: (v) => set((x) => x.copyWith(wavyProgress: v)),
                ),
              ),
              _Tile(
                title: 'Стекло',
                subtitle: 'Размытие под мини-плеером',
                trailing: Switch(
                  value: s.glass,
                  onChanged: (v) => set((x) => x.copyWith(glass: v)),
                ),
              ),
              if (Platform.isMacOS)
                _Tile(
                  title: 'Живая чёлка',
                  subtitle:
                      'На MacBook с вырезом: что играет — вокруг камеры, '
                      'наведи мышь для кнопок',
                  trailing: Switch(
                    value: s.notchIsland,
                    onChanged: (v) => set((x) => x.copyWith(notchIsland: v)),
                  ),
                ),
              _Tile(
                title: 'Меньше анимаций',
                subtitle:
                    'Фон замирает, списки появляются сразу. Бережёт батарею',
                trailing: Switch(
                  value: s.reduceMotion,
                  onChanged: (v) => set((x) => x.copyWith(reduceMotion: v)),
                ),
              ),
              const _Section('Last.fm'),
              const _LastFmTile(),
              const _Section('Горячие клавиши'),
              const _Hotkeys(),
              const _Section('О приложении'),
              const _About(),
            ],
          ),
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
                    'И музыка продолжится там,',
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
                    'где ты остановился',
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
        title: user == null ? 'Скробблинг выключен' : 'Вы вошли как $user',
        subtitle: user == null
            ? 'Отправлять прослушанное в профиль Last.fm'
            : 'Каждый трек, дослушанный до половины, попадает в профиль',
        trailing: TextButton(
          onPressed: user == null
              ? () => showDialog<void>(
                  context: context,
                  useRootNavigator: true,
                  builder: (_) => _LastFmDialog(lastFm),
                )
              : lastFm.signOut,
          child: Text(user == null ? 'Войти' : 'Выйти'),
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
          _error = 'Не получилось войти: проверь ключ, логин и пароль';
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
              const Text(
                'Last.fm выдаёт ключи каждому приложению отдельно. Создай '
                'свой бесплатно и вставь сюда — пароль не сохраняется.',
                style: TextStyle(color: SegueColors.textDim, fontSize: 13),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://www.last.fm/api/account/create'),
                ),
                child: const Text('Получить ключ на last.fm'),
              ),
              field(_key, 'API key'),
              field(_secret, 'Shared secret'),
              field(_user, 'Логин Last.fm'),
              field(_pass, 'Пароль', hide: true),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Входим…' : 'Войти'),
        ),
      ],
    );
  }
}

class _Hotkeys extends StatelessWidget {
  const _Hotkeys();

  static const _keys = [
    ('Пробел', 'Пауза / играть'),
    ('← →', 'Перемотка на 5 секунд'),
    ('⌘/Ctrl + ← →', 'Предыдущий / следующий трек'),
    ('⌘/Ctrl + ↑ ↓', 'Громкость'),
    ('M', 'Выключить звук'),
    ('L', 'В любимые'),
    ('⌘/Ctrl + F', 'Поиск'),
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
    return _Tile(
      title: 'Segue $appVersion',
      subtitle: update.isLoading
          ? 'Проверяем обновления…'
          : found == null
          ? 'У тебя последняя версия'
          : 'Вышла версия ${found.version}',
      trailing: found == null
          ? TextButton(
              onPressed: () => ref.invalidate(updateProvider),
              child: const Text('Проверить'),
            )
          : FilledButton(
              onPressed: () => launchUrl(Uri.parse(found.url)),
              child: const Text('Скачать'),
            ),
    );
  }
}
