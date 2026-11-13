import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/track_tile.dart';

import '../theme/artwork_colors.dart';

import '../../core/catalog/wave.dart';
import '../../core/catalog/wave_settings.dart';
import '../widgets/wave_art.dart';

import '../../core/catalog/deezer.dart';

import '../../core/library/library.dart';
import '../../core/library/library_store.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/collection.dart';
import '../widgets/import_dialog.dart';
import 'devices_screen.dart';
import '../widgets/motion.dart';
import '../widgets/nav.dart';
import '../widgets/track_actions.dart';
import 'library_screen.dart';
import 'playlist_screen.dart';
import '../widgets/slow_ticker.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Start page: quick access to liked songs and playlists, and what you
/// listened to recently.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Доброй ночи'.tr;
    if (h < 12) return 'Доброе утро'.tr;
    if (h < 18) return 'Добрый день'.tr;
    return 'Добрый вечер'.tr;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyPlayedProvider);
    final liked = ref.watch(likedTracksProvider);
    final playlists = ref.watch(playlistsProvider);
    final empty = recent.isEmpty && liked.isEmpty && playlists.isEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                ),
                const _WaveCard(),
                const SizedBox(height: 18),
                if (empty)
                  _Welcome(
                    onSearch: onOpenSearch,
                    onImported: (id) => pushUnique(
                      Navigator.of(context),
                      PlaylistScreen.route(id),
                    ),
                  )
                else ...[
                  _QuickGrid(
                    likedCount: liked.length,
                    likedCovers: [for (final t in liked.take(4)) t.artworkUrl],
                    playlists: playlists.take(5).toList(),
                    onLiked: () {
                      ref.read(librarySectionProvider.notifier).state =
                          LibrarySection.liked;
                      onOpenLibrary();
                    },
                  ),
                  if (recent.isNotEmpty) ...[
                    _SectionTitle('Недавно слушали'.tr),
                    _Shelf(tracks: recent.take(20).toList()),
                  ],
                  if (liked.isNotEmpty) ...[
                    _SectionTitle('Из любимого'.tr),
                    _Shelf(tracks: liked.take(20).toList()),
                  ],
                ],
                _SectionTitle('Чарты'.tr),
                const _Charts(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSearch, required this.onImported});

  final VoidCallback onSearch;
  final ValueChanged<String> onImported;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [
              SegueColors.accent.withValues(alpha: 0.28),
              const Color(0xFF8E5CFF).withValues(alpha: 0.18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 36),
            const SizedBox(height: 14),
            Text(
              'YouTube и SoundCloud в одном месте'.tr,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Без рекламы и аккаунта. Найди трек или перенеси плейлисты из Spotify и Яндекс Музыки — здесь появятся любимые, плейлисты и история.'
                  .tr,
              style: TextStyle(color: SegueColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                PressScale(
                  onTap: onSearch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: SegueColors.text,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, color: SegueColors.ink),
                        SizedBox(width: 8),
                        Text(
                          'Найти музыку'.tr,
                          style: TextStyle(
                            color: SegueColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PressScale(
                  onTap: () => showJoinDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login_rounded),
                        SizedBox(width: 8),
                        Text(
                          'Уже есть Segue? Войти по коду'.tr,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                PressScale(
                  onTap: () async {
                    final id = await showImportDialog(context);
                    if (id != null) onImported(id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded),
                        SizedBox(width: 8),
                        Text(
                          'Перенести плейлист'.tr,
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of quick tiles: liked songs and a few playlists.
class _QuickGrid extends ConsumerWidget {
  const _QuickGrid({
    required this.likedCount,
    required this.likedCovers,
    required this.playlists,
    required this.onLiked,
  });

  final int likedCount;
  final List<String?> likedCovers;
  final List<Playlist> playlists;
  final VoidCallback onLiked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = <Widget>[
      _QuickTile(
        cover: const CoverCollage(
          urls: [],
          size: 56,
          radius: 14,
          icon: Icons.favorite_rounded,
          gradient: likedGradient,
        ),
        title: 'Любимые'.tr,
        subtitle: tracksLabel(likedCount),
        playContext: 'liked',
        onTap: onLiked,
      ),
      for (final p in playlists)
        _QuickTile(
          cover: CoverCollage(urls: [p.coverUrl], size: 56, radius: 14),
          title: p.name,
          subtitle: tracksLabel(p.count),
          playContext: 'playlist:${p.id}',
          onTap: () =>
              pushUnique(Navigator.of(context), PlaylistScreen.route(p.id)),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 560 ? 3 : 2;
          final w = (c.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      ),
    );
  }
}

class _QuickTile extends ConsumerWidget {
  const _QuickTile({
    required this.cover,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.playContext,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The tile lights up while music from this list plays.
  final String? playContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(playerProvider);
    return ValueListenableBuilder<String?>(
      valueListenable: player.playContext,
      builder: (context, ctx, _) {
        final mine = playContext != null && ctx == playContext;
        final playing =
            mine && ref.watch(playingProvider.select((v) => v.value ?? false));
        final accent = mine
            ? ref.watch(currentColorsProvider.select((c) => c.accent))
            : SegueColors.text;
        return _tile(mine, playing, accent);
      },
    );
  }

  Widget _tile(bool mine, bool playing, Color accent) {
    return PressScale(
      scale: 0.97,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: mine
              ? accent.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            cover,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: mine ? accent : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SegueColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (mine)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 24,
                  height: 18,
                  child: EqualizerBars(active: playing, color: accent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    ),
  );
}

/// Horizontal row of big cover cards; tapping plays the row from there.
class _Shelf extends ConsumerWidget {
  const _Shelf({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final t = tracks[i];
          return StaggeredEntrance(
            index: i % 8,
            child: PressScale(
              onTap: () => ref.read(playerProvider).tapTrack(tracks, i),
              onLongPress: () => showTrackActions(context, ref, t),
              child: SizedBox(
                width: 148,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Artwork(url: t.artworkUrl, size: 148, radius: 20),
                    const SizedBox(height: 10),
                    Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      t.artist,
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
    );
  }
}

/// Big "Моя волна" card: an endless personal mix, one tap away.
class _WaveCard extends ConsumerStatefulWidget {
  const _WaveCard();

  @override
  ConsumerState<_WaveCard> createState() => _WaveCardState();
}

class _WaveCardState extends ConsumerState<_WaveCard> {
  bool _busy = false;

  /// Vivid colours of the card when nothing of the wave plays yet.
  static const _brand = [
    Color(0xFF5B3DF5),
    Color(0xFFFF4F8B),
    Color(0xFFFF9A3C),
    Color(0xFF2EC5FF),
  ];

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(waveProvider).myWave(ref.read(waveSettingsProvider));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Волна не запустилась. Проверь интернет'.tr)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.read(playerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final settings = ref.watch(waveSettingsProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final still = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<String?>(
      valueListenable: player.waveTitle,
      builder: (context, wave, _) {
        final mine = wave == Wave.myWaveTitle;
        final live = mine && playing;
        // While the wave plays, the card leans towards the cover's colour.
        final colors = [
          for (var i = 0; i < _brand.length; i++)
            mine && i.isOdd ? Color.lerp(_brand[i], accent, 0.45)! : _brand[i],
        ];
        void onTap() {
          if (!mine) {
            _start();
          } else {
            playing ? player.pause() : player.play();
          }
        }

        final summary = settings.summary;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PressScale(
            scale: 0.985,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                height: 190,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WaveArt(colors: colors, playing: live, animate: !still),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 22, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Spacer(),
                                Text(
                                  'Моя волна'.tr,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  live
                                      ? 'Играет — новые треки добавляются сами'
                                            .tr
                                      : mine
                                      ? 'На паузе'.tr
                                      : 'Бесконечный микс под тебя'.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                const Spacer(),
                                _TuneButton(
                                  label: summary.isEmpty
                                      ? 'Настроить'.tr
                                      : summary,
                                  active: summary.isNotEmpty,
                                  onTap: () => showWaveSettings(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _WavePlayButton(
                            busy: _busy,
                            live: live,
                            onTap: onTap,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TuneButton extends StatelessWidget {
  const _TuneButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White play button; while the wave plays it shows dancing bars inside
/// and soft rings pulsing out of it like sound.
class _WavePlayButton extends StatefulWidget {
  const _WavePlayButton({
    required this.busy,
    required this.live,
    required this.onTap,
  });

  final bool busy;
  final bool live;
  final VoidCallback onTap;

  @override
  State<_WavePlayButton> createState() => _WavePlayButtonState();
}

class _WavePlayButtonState extends State<_WavePlayButton>
    with SlowTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_WavePlayButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.live && !_c.isAnimating) _c.repeat();
    if (!widget.live && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 70.0;
    return PressScale(
      scale: 0.9,
      onTap: widget.onTap,
      child: SizedBox(
        width: size + 44,
        height: size + 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.live)
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < 2; i++)
                      Builder(
                        builder: (context) {
                          final p = (_c.value + i / 2) % 1;
                          return Container(
                            width: size + 44 * p,
                            height: size + 44 * p,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(
                                  alpha: 0.5 * (1 - p),
                                ),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            AnimatedContainer(
              duration: SegueMotion.medium,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(
                      alpha: widget.live ? 0.35 : 0.12,
                    ),
                    blurRadius: widget.live ? 28 : 12,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: SegueMotion.medium,
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: widget.busy
                    ? const Padding(
                        key: ValueKey('busy'),
                        padding: EdgeInsets.all(22),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: SegueColors.ink,
                        ),
                      )
                    : widget.live
                    ? const SizedBox(
                        key: ValueKey('live'),
                        width: 26,
                        height: 24,
                        child: EqualizerBars(
                          active: true,
                          color: SegueColors.ink,
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        key: ValueKey('play'),
                        size: 40,
                        color: SegueColors.ink,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Настроить волну": activity, character, mood and language, as in
/// Yandex Music. A playing wave picks the new settings up right away.
Future<void> showWaveSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SegueColors.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _WaveSettingsSheet(),
    );

class _WaveSettingsSheet extends ConsumerStatefulWidget {
  const _WaveSettingsSheet();

  @override
  ConsumerState<_WaveSettingsSheet> createState() => _WaveSettingsSheetState();
}

class _WaveSettingsSheetState extends ConsumerState<_WaveSettingsSheet> {
  // Read up front: ref can't be used any more in dispose().
  late final _initial = ref.read(waveSettingsProvider);
  late final _wave = ref.read(waveProvider);
  late final _player = ref.read(playerProvider);
  late WaveSettings _latest = _initial;

  @override
  void initState() {
    super.initState();
    _wave;
    _player;
  }

  @override
  Widget build(BuildContext context) {
    final s = _latest = ref.watch(waveSettingsProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    void set(WaveSettings v) => ref.read(waveSettingsProvider.notifier).set(v);

    Widget group(
      String title,
      List<String> options,
      String? value,
      WaveSettings Function(WaveSettings, String?) apply,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: SegueColors.textDim,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                PressScale(
                  // Tap again to clear: every group is optional.
                  // From the latest state: quick taps mustn't undo each other.
                  onTap: () => set(
                    apply(
                      ref.read(waveSettingsProvider),
                      o == value ? null : o,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: SegueMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: o == value
                          ? accent
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      o.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: o == value ? SegueColors.ink : SegueColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Настроить волну'.tr,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                if (!s.isEmpty)
                  TextButton(
                    onPressed: () => set(const WaveSettings()),
                    child: Text('Сбросить'.tr),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            group(
              'Под занятие'.tr,
              WaveSettings.activities,
              s.activity,
              (cur, v) => cur.copyWith(activity: () => v),
            ),
            group(
              'По характеру'.tr,
              WaveSettings.characters,
              s.character,
              (cur, v) => cur.copyWith(character: () => v),
            ),
            group(
              'Под настроение'.tr,
              WaveSettings.moods,
              s.mood,
              (cur, v) => cur.copyWith(mood: () => v),
            ),
            group(
              'По языку'.tr,
              WaveSettings.languages,
              s.language,
              (cur, v) => cur.copyWith(language: () => v),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: SegueColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.waves_rounded),
                label: Text(
                  'Слушать'.tr,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _play(s);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Closed without "Слушать": a running wave still switches to the
    // new settings.
    if (!_played &&
        _latest != _initial &&
        _player.waveTitle.value == Wave.myWaveTitle) {
      _play(_latest);
    }
    super.dispose();
  }

  bool _played = false;

  void _play(WaveSettings s) {
    _played = true;
    _wave.myWave(s).catchError((Object _) {});
  }
}

/// Top tracks from the Deezer charts, by genre.
class _Charts extends ConsumerStatefulWidget {
  const _Charts();

  @override
  ConsumerState<_Charts> createState() => _ChartsState();
}

class _ChartsState extends ConsumerState<_Charts> {
  int _genre = 0;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final chart = ref.watch(chartProvider(_genre));
    final accent = ref.watch(currentColorsProvider).accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final g in Catalog.genres.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PressScale(
                    onTap: () => setState(() {
                      _genre = g.key;
                      _all = false;
                    }),
                    child: AnimatedContainer(
                      duration: SegueMotion.medium,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: g.key == _genre
                            ? accent.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        g.value.tr,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: g.key == _genre ? accent : SegueColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        chart.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Чарты сейчас недоступны'.tr,
              style: TextStyle(color: SegueColors.textDim),
            ),
          ),
          data: (tracks) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                for (var i = 0; i < tracks.length && (i < 10 || _all); i++)
                  Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SegueColors.textDim,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TrackTile(tracks: tracks, index: i),
                      ),
                    ],
                  ),
                if (!_all && tracks.length > 10)
                  TextButton(
                    onPressed: () => setState(() => _all = true),
                    child: Text('Показать все {0}'.trArgs([tracks.length])),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
