import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'now_playing_screen.dart';

import '../../core/settings/settings.dart';
import '../../core/integrations/notch.dart';
import '../../core/integrations/updates.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library.dart';
import '../../core/player/audio_fx.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../app_nav.dart';
import '../widgets/collection.dart';
import '../widgets/import_dialog.dart';
import '../widgets/mini_player.dart';
import '../widgets/remote_bar.dart';
import '../widgets/jam_sheet.dart';
import '../../core/sync/jam.dart';
import '../../core/sync/connect.dart';
import '../widgets/motion.dart';
import '../widgets/nav.dart';
import '../widgets/track_actions.dart';
import '../../core/downloads/downloads.dart';
import '../../core/sync/sync.dart';
import 'devices_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// App frame: tabs (Home, Search, Library) each with their own navigation
/// stack, the mini player, and a sidebar on wide screens or a bottom bar
/// on phones.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _tab = 0;

  /// 0 Home, 1 Search, 2 Library, 3 Devices, 4 Settings.
  final _navigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  StreamSubscription<String>? _errors;
  StreamSubscription<String>? _handoffs;
  StreamSubscription<String>? _relayHandoffs;
  StreamSubscription<String>? _jamEvents;
  StreamSubscription<String>? _downloadErrors;

  @override
  void initState() {
    super.initState();
    AppNav.pushInTab = (route) {
      // From a dialog/sheet or the full-screen player: back to the shell.
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      pushUnique(_navigators[_tab].currentState, route);
    };
    // Sound settings follow the player (and are restored on launch).
    ref.listenManual(
      audioFxProvider,
      (_, fx) => ref.read(playerProvider).applyFx(fx),
      fireImmediately: true,
    );
    ref.listenManual(
      settingsProvider.select((s) => s.fadeSeconds),
      (_, v) => ref.read(playerProvider).fadeSeconds = v,
      fireImmediately: true,
    );
    HardwareKeyboard.instance.addHandler(_onKey);
    // MacBook notch: now playing in the colours of the cover.
    if (NotchBridge.supported) {
      final connect = ref.read(connectProvider);
      final library = ref.read(libraryProvider);
      final notch = NotchBridge(
        ref.read(playerProvider),
        isLiked: library.isLiked,
        toggleLike: (t) => library.setLiked(t, !library.isLiked(t)),
        onOpen: () {
          final nav = Navigator.of(context, rootNavigator: true);
          if (topRouteName(nav) != NowPlayingScreen.routeName) {
            nav.push(NowPlayingScreen.route());
          }
        },
        remote: () => connect.playingElsewhere?.remote,
        remoteCommand: connect.command,
        setVolume: _volume,
      )..attach();
      _notch = notch;
      // Likes and other devices' playback change what it shows.
      library.changes.listen((_) => notch.refresh());
      connect.relay.devices.addListener(notch.refresh);
      ref.listenManual(
        currentColorsProvider,
        (_, c) => notch.accent = c.accent,
        fireImmediately: true,
      );
      ref.listenManual(
        settingsProvider.select((s) => s.notchIsland),
        (_, on) => notch.setEnabled(on),
        fireImmediately: true,
      );
    }
    // segue://pair links: a QR scanned with the phone's camera app.
    final links = AppLinks();
    _links = links.uriLinkStream.listen(_onLink);
    links.getInitialLink().then((u) {
      if (u != null) _onLink(u);
    }).ignore();
    // A newer release on GitHub: say so once, quietly.
    ref.listenManual(updateProvider, (_, next) {
      final u = next.value;
      if (u != null) _toast('Вышла версия ${u.version} — см. Настройки');
    }, fireImmediately: true);
    _errors = ref.read(playerProvider).errors.stream.listen((msg) {
      if (!mounted) return;
      _toast(msg);
    });
    _downloadErrors = ref.read(downloadsProvider).errors.stream.listen((msg) {
      if (!mounted) return;
      _toast(msg);
    });
    _jamEvents = ref.read(jamProvider).events.stream.listen((e) {
      if (mounted) _toast(e);
    });
    _relayHandoffs = ref.read(connectProvider).relay.incoming.stream.listen((
      from,
    ) {
      if (mounted) _toast('Продолжаем музыку с «$from»');
    });
    _handoffs = ref.read(syncProvider).incomingHandoff.stream.listen((from) {
      if (!mounted) return;
      _toast('Продолжаем музыку с «$from»');
    });
  }

  /// Messages pop up above the mini player and beside the sidebar, not
  /// over them: the content area has its own messenger and scaffold with
  /// the player as its bottom bar.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  Widget _framed(Widget content, Widget bottom) => ScaffoldMessenger(
    key: _messenger,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: content,
      // In a Column so the player keeps its natural height (a bottom bar
      // is otherwise allowed to grow as tall as the screen).
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const JamBar(), const RemoteBar(), bottom],
      ),
    ),
  );

  void _toast(String msg) => _messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  StreamSubscription<Uri>? _links;
  NotchBridge? _notch;

  Future<void> _onLink(Uri uri) async {
    if (uri.scheme == 'segue' && uri.host == 'jam') {
      _toast('Подключаемся к совместному прослушиванию…');
      try {
        final host = await ref.read(jamProvider).join(uri.toString());
        _toast('Слушаешь вместе с $host');
      } catch (e) {
        _toast('$e'.replaceFirst('Bad state: ', ''));
      }
      return;
    }
    if (uri.scheme != 'segue' || uri.host != 'pair') return;
    final connect = ref.read(connectProvider);
    _toast('Связываем устройства…');
    // Right after launch the relay may still be connecting.
    for (var i = 0; i < 20 && !connect.relay.connected.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    try {
      final name = await connect.join(uri.toString());
      _toast('Готово: связано с «$name». Музыка уже едет');
    } catch (e) {
      _toast('$e');
    }
  }

  /// Keyboard shortcuts (see the list in Settings). Typing in a text
  /// field is never intercepted.
  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context?.widget;
    if (focus is EditableText) return false;
    final player = ref.read(playerProvider);
    final keys = HardwareKeyboard.instance;
    final mod = keys.isMetaPressed || keys.isControlPressed;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.keyF && mod) {
      _select(1);
      return true;
    }
    if (player.current == null) return false;
    void seekBy(int seconds) {
      final pos = ref.read(positionProvider).value ?? Duration.zero;
      final to = pos + Duration(seconds: seconds);
      player.seek(to.isNegative ? Duration.zero : to);
    }

    if (k == LogicalKeyboardKey.space && !repeat) {
      (ref.read(playingProvider).value ?? false)
          ? player.pause()
          : player.play();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      mod ? (repeat ? null : player.skipToNext()) : seekBy(5);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      mod ? (repeat ? null : player.skipToPrevious()) : seekBy(-5);
    } else if (k == LogicalKeyboardKey.arrowUp && mod) {
      _volume(player.volume.value + 0.05);
    } else if (k == LogicalKeyboardKey.arrowDown && mod) {
      _volume(player.volume.value - 0.05);
    } else if (k == LogicalKeyboardKey.keyM && !mod && !repeat) {
      if (player.volume.value > 0) {
        _beforeMute = player.volume.value;
        _volume(0);
      } else {
        _volume(_beforeMute);
      }
    } else if (k == LogicalKeyboardKey.keyL && !mod && !repeat) {
      final t = player.current!;
      final library = ref.read(libraryProvider);
      library.setLiked(t, !library.isLiked(t));
    } else {
      return false;
    }
    return true;
  }

  double _beforeMute = 1;

  void _volume(double v) {
    final player = ref.read(playerProvider);
    player.setVolume(v);
    ref.read(libraryProvider).setMeta('volume', '${player.volume.value}');
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _errors?.cancel();
    _handoffs?.cancel();
    _relayHandoffs?.cancel();
    _jamEvents?.cancel();
    _links?.cancel();
    _notch?.dispose();
    _downloadErrors?.cancel();
    super.dispose();
  }

  /// Every section opens at its own start page: a menu item always shows
  /// that section, never a page left open inside it earlier.
  void _select(int tab) {
    _navigators[tab].currentState?.popUntil((r) => r.isFirst);
    setState(() => _tab = tab);
  }

  void _openDevices() => _select(3);
  void _openSettings() => _select(4);

  void _openPlaylist(String id) {
    setState(() => _tab = 2);
    final nav = _navigators[2].currentState;
    if (nav == null) return;
    final route = PlaylistScreen.route(id);
    if (topRouteName(nav) == route.settings.name) return; // already open
    nav.popUntil((r) => r.isFirst);
    nav.push(route);
  }

  Widget _tabNavigator(int i, Widget root) => Navigator(
    key: _navigators[i],
    onGenerateRoute: (_) => PageRouteBuilder(
      pageBuilder: (_, _, _) => root,
      transitionDuration: Duration.zero,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(currentColorsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = IndexedStack(
      index: _tab,
      children: [
        _tabNavigator(
          0,
          HomeScreen(
            onOpenSearch: () => _select(1),
            onOpenLibrary: () => _select(2),
          ),
        ),
        _tabNavigator(1, const SearchScreen()),
        _tabNavigator(2, const LibraryScreen()),
        _tabNavigator(3, const DevicesScreen()),
        _tabNavigator(4, const SettingsScreen()),
      ],
    );

    return PopScope(
      // Android back: pop inside the current tab first.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        final nav = _navigators[_tab].currentState;
        if (nav != null && await nav.maybePop()) return;
        if (_tab != 0) setState(() => _tab = 0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Ambient glow in the colour of what's playing.
            Positioned(
              top: -220,
              left: -120,
              right: -120,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 1200),
                height: 480,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      colors.accent.withValues(alpha: 0.16),
                      colors.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            if (wide)
              Row(
                children: [
                  _Sidebar(
                    tab: _tab,
                    onSelect: _select,
                    onPlaylist: _openPlaylist,
                    onDevices: _openDevices,
                    onSettings: _openSettings,
                  ),
                  Expanded(
                    child: _framed(
                      content,
                      const SafeArea(top: false, child: MiniPlayer()),
                    ),
                  ),
                ],
              )
            else
              _framed(
                content,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MiniPlayer(),
                    _BottomBar(tab: _tab, onSelect: _select),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _items = [
  (Icons.home_rounded, Icons.home_outlined, 'Главная'),
  (Icons.search_rounded, Icons.search_rounded, 'Поиск'),
  (Icons.library_music_rounded, Icons.library_music_outlined, 'Библиотека'),
];

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.tab, required this.onSelect});

  final int tab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SegueColors.ink,
        border: Border(top: BorderSide(color: SegueColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (final (i, (on, off, label)) in _items.indexed)
                Expanded(
                  child: PressScale(
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: SegueMotion.medium,
                          curve: SegueMotion.spring,
                          padding: EdgeInsets.symmetric(
                            horizontal: i == tab ? 18 : 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: i == tab
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            i == tab ? on : off,
                            color: i == tab
                                ? SegueColors.text
                                : SegueColors.textDim,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i == tab
                                ? SegueColors.text
                                : SegueColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.tab,
    required this.onSelect,
    required this.onPlaylist,
    required this.onDevices,
    required this.onSettings,
  });

  final int tab;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onPlaylist;
  final VoidCallback onDevices;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: Color(0x660B0B0D),
        border: Border(right: BorderSide(color: SegueColors.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 24, 24, 20),
              child: _Logo(),
            ),
            for (final (i, (on, off, label)) in _items.indexed)
              _SideItem(
                icon: i == tab ? on : off,
                label: label,
                selected: i == tab,
                onTap: () => onSelect(i),
              ),
            _SideItem(
              icon: Icons.devices_rounded,
              label: 'Устройства',
              selected: tab == 3,
              onTap: onDevices,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 12, 8),
              child: Text(
                'ПЛЕЙЛИСТЫ',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: SegueColors.textDim,
                ),
              ),
            ),
            _SideItem(
              icon: Icons.add_rounded,
              label: 'Новый плейлист',
              selected: false,
              onTap: () async {
                final name = await askPlaylistName(context);
                if (name == null) return;
                onPlaylist(ref.read(libraryProvider).createPlaylist(name));
              },
            ),
            _SideItem(
              icon: Icons.download_rounded,
              label: 'Импорт по ссылке',
              selected: false,
              onTap: () async {
                final id = await showImportDialog(context);
                if (id != null) onPlaylist(id);
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final p in playlists)
                    PressScale(
                      scale: 0.97,
                      onTap: () => onPlaylist(p.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            CoverCollage(
                              urls: [p.coverUrl],
                              size: 36,
                              radius: 9,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _SideItem(
              icon: Icons.tune_rounded,
              label: 'Настройки',
              selected: tab == 4,
              onTap: onSettings,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// The Segue mark and wordmark. The mark breathes softly while music plays.
class _Logo extends ConsumerWidget {
  const _Logo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playingProvider).value ?? false;
    return Row(
      children: [
        _Breathing(
          active: playing && !MediaQuery.disableAnimationsOf(context),
          child: Image.asset(
            'assets/brand/mark_256.png',
            width: 38,
            height: 38,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'segue',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
      ],
    );
  }
}

class _Breathing extends StatefulWidget {
  const _Breathing({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Breathing old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.animateTo(0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

class _SideItem extends ConsumerWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(currentColorsProvider).accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: PressScale(
        scale: 0.97,
        hoverRadius: 14,
        onTap: onTap,
        child: AnimatedContainer(
          duration: SegueMotion.medium,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? accent : SegueColors.textDim),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? SegueColors.text : SegueColors.textDim,
                  ),
                ),
              ),
              // A dot in the accent colour marks where you are.
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: SegueMotion.medium,
                curve: SegueMotion.spring,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
