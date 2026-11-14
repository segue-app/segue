import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dj/auto_dj.dart';
import '../../core/dj/beat_grid.dart';
import '../../core/l10n/l10n.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/player/player_handler.dart';
import '../../core/settings/settings.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';

/// Two decks: the song playing and the next one, their tempo and beats,
/// and the crossfade between them as it happens.
class DjScreen extends ConsumerStatefulWidget {
  const DjScreen({super.key});

  // Opaque once it's in: the screen below stops drawing.
  static Route<void> route() => PageRouteBuilder(
    pageBuilder: (_, _, _) => const DjScreen(),
    transitionsBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: SegueMotion.ease),
      child: child,
    ),
  );

  @override
  ConsumerState<DjScreen> createState() => _DjScreenState();
}

/// Where one deck's song is, smooth from frame to frame. The player tells
/// its position only every so often; between, it runs on by itself and
/// eases onto each new report instead of jumping to it.
class _DeckClock {
  double t = 0;
  double? _raw;
  String? _key;
  final _since = Stopwatch()..start();

  void update(
    Duration? raw,
    String? key,
    double speed,
    bool running,
    double dt,
  ) {
    if (raw == null) return;
    final r = raw.inMicroseconds / 1e6;
    if (r != _raw || !running) {
      _raw = r;
      _since
        ..reset()
        ..start();
    }
    final target = running ? r + _since.elapsedMicroseconds / 1e6 * speed : r;
    if (key != _key || (target - t).abs() > 0.4) {
      _key = key;
      t = target;
      return;
    }
    if (running) t += dt * speed;
    t += (target - t) * math.min(1.0, dt * 5);
  }
}

/// The moving parts of the screen, every display frame: both decks' time
/// and the crossfade. Only what draws them listens; the rest of the screen
/// is rebuilt a few times a second.
class _Clock extends ChangeNotifier {
  final a = _DeckClock(), b = _DeckClock();
  double progress = 0;

  /// How loud each deck shows (its frame and glow), eased: when a mix ends
  /// and the decks change songs, the light moves across instead of
  /// jumping.
  double levelA = 1, levelB = 0;

  void tick(SegueAudioHandler player, DjState s, double dt) {
    final c = player.djClock;
    final before = (a.t, b.t, progress);
    a.update(c.outgoing, s.outgoing?.key, s.outgoingSpeed, c.playing, dt);
    b.update(
      c.incoming,
      s.incoming?.key,
      s.incomingSpeed,
      c.playing && !s.waitingForBar,
      dt,
    );
    final p = s.mixing ? c.progress : 0.0;
    final ta = s.mixing ? math.cos(progress * math.pi / 2) : 1.0;
    final tb = s.mixing ? math.sin(progress * math.pi / 2) : 0.0;
    final k = math.min(1.0, dt * 3);
    levelA += (ta - levelA) * k;
    levelB += (tb - levelB) * k;
    progress = (p - progress).abs() > 0.3
        ? p
        : progress + (p - progress) * math.min(1.0, dt * 12);
    if (before != (a.t, b.t, progress) ||
        (ta - levelA).abs() > 0.002 ||
        (tb - levelB).abs() > 0.002) {
      notifyListeners();
    }
  }
}

class _DjScreenState extends ConsumerState<DjScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Timer _slow;
  late DjState _state = ref.read(playerProvider).dj;
  final _clock = _Clock();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Decks and lights move on every display frame, and only they redraw.
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
      _last = elapsed;
      _clock.tick(ref.read(playerProvider), _state, dt);
    })..start();
    // Names, tempo, status: four times a second is plenty.
    _slow = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _state = ref.read(playerProvider).dj);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _slow.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final settings = ref.watch(settingsProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final player = ref.read(playerProvider);
    final auto = ref.watch(autoDjProvider);
    void set(AppSettings Function(AppSettings) f) =>
        ref.read(settingsProvider.notifier).update(f);

    final deckA = _Deck(
      label: s.mixing ? 'A · уходит'.tr : 'A · играет'.tr,
      track: s.outgoing,
      grid: s.outgoingGrid,
      clock: _clock,
      time: () => _clock.a.t,
      speed: s.outgoingSpeed,
      turning: s.playing,
      level: () => _clock.levelA,
      accent: accent,
    );
    final deckB = _Deck(
      label: s.mixing ? 'B · входит'.tr : 'B · следующий'.tr,
      track: s.incoming,
      grid: s.incomingGrid,
      clock: _clock,
      time: () => s.mixing ? _clock.b.t : null,
      speed: s.incomingSpeed,
      turning: s.mixing && !s.waitingForBar && s.playing,
      level: () => _clock.levelB,
      accent: accent,
    );

    return Scaffold(
      backgroundColor: SegueColors.ink,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.3,
            colors: [accent.withValues(alpha: 0.14), SegueColors.ink],
          ),
        ),
        child: SafeArea(
          child: _PullToClose(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 760;
                return ListView(
                  // Pulled down past the top, it closes the screen.
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: math.max(16, (box.maxWidth - 1000) / 2),
                    vertical: 12,
                  ),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Закрыть'.tr,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'DJ',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        const Spacer(),
                        if (s.beatMatched && s.mixing)
                          _Badge(text: 'Доли совпадают'.tr, color: accent),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Side by side on every screen, as on a real mixer.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: deckA),
                        SizedBox(width: wide ? 18 : 10),
                        Expanded(child: deckB),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _Crossfader(clock: _clock, accent: accent),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        _status(s, settings),
                        style: const TextStyle(
                          color: SegueColors.textDim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: SegueColors.ink,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 16,
                          ),
                        ),
                        onPressed: s.mixing || s.incoming == null
                            ? null
                            : () {
                                if (settings.fadeSeconds < 1) {
                                  set((x) => x.copyWith(fadeSeconds: 8));
                                }
                                player.mixNow();
                              },
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: Text('Свести сейчас'.tr),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Panel(
                      children: [
                        _Row(
                          title: 'Длина перехода'.tr,
                          trailing: Text(
                            settings.fadeSeconds < 1
                                ? 'выкл'.tr
                                : '{0} с'.trArgs([
                                    settings.fadeSeconds.round(),
                                  ]),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Slider(
                          value: settings.fadeSeconds.clamp(0, 16),
                          max: 16,
                          divisions: 16,
                          onChanged: (v) => set(
                            (x) => x.copyWith(fadeSeconds: v.roundToDouble()),
                          ),
                        ),
                        _Row(
                          title: 'Подгонять темп и доли'.tr,
                          subtitle: 'Следующая песня встаёт в темп и на сильную долю текущей'
                              .tr,
                          trailing: Switch(
                            value: settings.matchTempo,
                            onChanged: (v) =>
                                set((x) => x.copyWith(matchTempo: v)),
                          ),
                        ),
                      ],
                    ),
                    if (auto != null) ...[
                      const SizedBox(height: 14),
                      _AutoPanel(
                        auto: auto,
                        accent: accent,
                        onTurnOn: () {
                          // Auto DJ mixes every song, beats lined up.
                          set(
                            (x) => x.copyWith(
                              fadeSeconds: x.fadeSeconds < 1
                                  ? 8
                                  : x.fadeSeconds,
                              matchTempo: true,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _status(DjState s, AppSettings settings) {
    if (s.incoming == null && !s.mixing) return 'Следующего трека нет'.tr;
    if (s.mixing) {
      if (s.waitingForBar) return 'Ждём начало такта…'.tr;
      return 'Сводим · {0}%'.trArgs([(s.progress * 100).round()]);
    }
    if (settings.fadeSeconds < 1) return 'Автоматическое сведение выключено'.tr;
    final u = s.untilMix;
    if (u == null) return '';
    final m = u.inMinutes;
    final sec = (u.inSeconds % 60).toString().padLeft(2, '0');
    return 'Переход через {0}'.trArgs(['$m:$sec']);
  }
}

/// Swipe down from the top (a finger, or two on a trackpad) and the
/// screen follows and closes; let go early and it springs back.
class _PullToClose extends StatefulWidget {
  const _PullToClose({required this.child});

  final Widget child;

  @override
  State<_PullToClose> createState() => _PullToCloseState();
}

class _PullToCloseState extends State<_PullToClose>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: SegueMotion.medium,
  )..addListener(() => setState(() => _y = _from * (1 - _curve.value)));
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _back,
    curve: SegueMotion.spring,
  );
  double _y = 0, _from = 0;
  bool _closing = false;

  static const _closeAt = 120.0;

  bool _onScroll(ScrollNotification n) {
    if (_closing || n.depth != 0) return false;
    if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      _back.stop();
      setState(() => _y = (_y - n.overscroll).clamp(0.0, 400.0));
    } else if (n is ScrollUpdateNotification &&
        _y > 0 &&
        (n.scrollDelta ?? 0) > 0) {
      // Pushed back up: the screen goes up first.
      setState(() => _y = math.max(0, _y - n.scrollDelta!));
    } else if (n is ScrollEndNotification && _y > 0) {
      final v = n.dragDetails?.primaryVelocity ?? 0;
      if (_y > _closeAt || (v > 700 && _y > 24)) {
        _closing = true;
        Navigator.of(context).maybePop();
      } else {
        _from = _y;
        _back.forward(from: 0);
      }
    }
    return false;
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The same tree at rest and while pulled, so the list keeps its drag.
    return Transform.translate(
      offset: Offset(0, _y),
      child: Opacity(
        opacity: (1 - _y / 500).clamp(0.4, 1.0),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Deck extends StatelessWidget {
  const _Deck({
    required this.label,
    required this.track,
    required this.grid,
    required this.clock,
    required this.time,
    required this.speed,
    required this.turning,
    required this.level,
    required this.accent,
  });

  final String label;
  final Track? track;
  final BeatGrid? grid;
  final Listenable clock;

  /// Where its song is now (seconds), or null when it isn't playing yet.
  final double? Function() time;
  final double speed;
  final bool turning;

  /// How loud this deck is in the mix (0..1).
  final double Function() level;
  final Color accent;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => _build(c.maxWidth < 330));

  /// [compact]: half a phone's width, so smaller type and the beat
  /// lights under the tempo.
  Widget _build(bool compact) {
    final g = grid;
    final bpm = g == null ? null : g.bpm * speed;
    final pitch = (speed - 1) * 100;
    final tempo = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            bpm == null ? '—' : bpm.toStringAsFixed(1),
            style: TextStyle(
              fontSize: compact ? 24 : 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 5),
            child: Text(
              'BPM',
              style: TextStyle(
                color: SegueColors.textDim,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11.5 : null,
              ),
            ),
          ),
          if (bpm != null && pitch.abs() >= 0.05) ...[
            const SizedBox(width: 8),
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 4 : 5),
              child: Text(
                '${pitch > 0 ? '+' : '−'}${pitch.abs().toStringAsFixed(1)}%',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 11.5 : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final lights = Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 8),
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(4 * 20 - 6, 14),
          painter: _BeatLights(
            clock: clock,
            grid: g,
            time: time,
            on: turning,
            accent: accent,
          ),
        ),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 10.5 : 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: SegueColors.textDim,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        Center(
          child: _Disc(
            url: track?.artworkUrl,
            clock: clock,
            // 33⅓ turns a minute, with the song: stops when it does.
            angle: () => (time() ?? 0) * 2 * math.pi * 33.333 / 60,
            glow: () => accent.withValues(alpha: 0.35 * level()),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          track?.displayTitle ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 14.5 : 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          track?.artist ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: SegueColors.textDim,
            fontSize: compact ? 12.5 : null,
          ),
        ),
        SizedBox(height: compact ? 8 : 14),
        if (compact) ...[
          tempo,
          const SizedBox(height: 8),
          lights,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: tempo),
              lights,
            ],
          ),
        if (g != null && !g.reliable)
          Text(
            'Доли нечёткие: сведём без них'.tr,
            style: const TextStyle(color: SegueColors.textDim, fontSize: 12),
          ),
      ],
    );
    // The frame brightens as the deck gets louder; what's inside it is
    // drawn once and kept.
    return AnimatedBuilder(
      animation: clock,
      // A new song on this deck slides in as the old one slides away.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 900),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, a) {
          final incoming = child.key == ValueKey(track?.key);
          return FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: Offset(incoming ? 0.12 : -0.12, 0),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(track?.key),
          child: RepaintBoundary(child: content),
        ),
      ),
      builder: (context, child) => Container(
        padding: EdgeInsets.all(compact ? 12 : 18),
        clipBehavior: Clip.antiAlias, // the song sliding away stays inside
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(compact ? 20 : 26),
          border: Border.all(
            color: accent.withValues(
              alpha: ((0.15 + 0.45 * level()) * 50).round() / 50,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Four lights, one per beat of the bar: the one on the beat flares and
/// fades until the next. The first of the bar in the accent colour.
class _BeatLights extends CustomPainter {
  _BeatLights({
    required Listenable clock,
    required this.grid,
    required this.time,
    required this.on,
    required this.accent,
  }) : super(repaint: clock);

  final BeatGrid? grid;
  final double? Function() time;
  final bool on;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final g = grid, t = time();
    int? beat;
    var flash = 0.0;
    if (on && g != null && t != null && g.reliable) {
      final x = (t - g.firstBeat) / g.period;
      final k = x.floor();
      beat = (k - g.downbeat) % 4;
      flash = math.exp(-(x - k) * 3.5);
    }
    final idle = Colors.white.withValues(alpha: 0.12);
    for (var i = 0; i < 4; i++) {
      final c = Offset(7 + i * 20.0, size.height / 2);
      final lit = beat == i ? flash : 0.0;
      final color = Color.lerp(idle, i == 0 ? accent : Colors.white, lit)!;
      if (lit > 0.05) {
        canvas.drawCircle(
          c,
          7 + 5 * lit,
          Paint()
            ..color = color.withValues(alpha: 0.3 * lit)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawCircle(c, 7, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_BeatLights old) =>
      old.grid != grid || old.on != on || old.accent != accent;
}

/// A record: grooves, the cover as its label, turning with the song. The
/// record is drawn once; each frame only turns it.
class _Disc extends StatelessWidget {
  const _Disc({
    required this.url,
    required this.clock,
    required this.angle,
    required this.glow,
  });

  final String? url;
  final Listenable clock;
  final double Function() angle;
  final Color Function() glow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Bigger share of a narrow deck (a phone shows two side by side).
        final size = math.min(
          220.0,
          c.maxWidth * (c.maxWidth < 260 ? 0.92 : 0.7),
        );
        final record = RepaintBoundary(
          child: CustomPaint(
            painter: const _GroovesPainter(),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1A1A1E),
                ),
                child: ClipOval(
                  child: Artwork(url: url, size: size * 0.42, radius: 0),
                ),
              ),
            ),
          ),
        );
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The glow, only redrawn when the mix changes it.
              AnimatedBuilder(
                animation: clock,
                builder: (context, _) {
                  final g = glow();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: g.a < 0.01
                          ? null
                          : [
                              BoxShadow(
                                color: g.withValues(
                                  alpha: (g.a * 40).round() / 40,
                                ),
                                blurRadius: 40,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: clock,
                child: record,
                builder: (context, child) =>
                    Transform.rotate(angle: angle(), child: child),
              ),
              // Light falls on the record from one side and stays there
              // while it turns, as on a real one.
              const IgnorePointer(child: CustomPaint(painter: _SheenPainter())),
              // The spindle.
              Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFCFCFD4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GroovesPainter extends CustomPainter {
  const _GroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0B0B0D));
    // Grooves of slightly different shades.
    final rnd = math.Random(7);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var k = r * 0.25; k < r * 0.96; k += 2.6) {
      groove.color = Colors.white.withValues(
        alpha: 0.03 + rnd.nextDouble() * 0.04,
      );
      canvas.drawCircle(c, k, groove);
    }
    // The gap between two songs on the record, and its edge.
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.6),
    );
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.08),
    );
  }

  @override
  bool shouldRepaint(_GroovesPainter old) => false;
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(
      Path()
        ..addOval(rect)
        ..addOval(Rect.fromCircle(center: c, radius: r * 0.24))
        ..fillType = PathFillType.evenOdd,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.08, 0.18, 0.5, 0.58, 0.68, 1],
          transform: const GradientRotation(-1.2),
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SheenPainter old) => false;
}

class _Crossfader extends StatelessWidget {
  const _Crossfader({required this.clock, required this.accent});

  final _Clock clock;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('A', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final knob = Container(
                width: 44,
                height: 26,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
              return SizedBox(
                height: 28,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: clock,
                      child: knob,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(
                          (c.maxWidth - 44) * clock.progress.clamp(0.0, 1.0),
                          0,
                        ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        const Text('B', style: TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(children: children),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(color: SegueColors.textDim)),
    trailing: trailing,
  );
}

class _AutoPanel extends StatelessWidget {
  const _AutoPanel({
    required this.auto,
    required this.accent,
    required this.onTurnOn,
  });

  final AutoDj auto;
  final Color accent;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auto.on, auto.status]),
      builder: (context, _) => _Panel(
        children: [
          _Row(
            title: 'Авто-DJ'.tr,
            subtitle: 'Сам сводит весь плейлист: выстраивает треки по темпу и энергии и заранее скачивает их, чтобы музыка не прервалась без интернета'
                .tr,
            trailing: Switch(
              value: auto.on.value,
              onChanged: (v) {
                if (v) onTurnOn();
                auto.setOn(v);
              },
            ),
          ),
          if (auto.on.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => auto.arrange(),
                    icon: const Icon(Icons.auto_graph_rounded),
                    label: Text('Выстроить сет'.tr),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      auto.status.value ?? '',
                      style: const TextStyle(color: SegueColors.textDim),
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
