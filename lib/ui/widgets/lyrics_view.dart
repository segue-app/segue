import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/lyrics/translate.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/settings/settings.dart';
import '../theme/theme.dart';
import 'depth.dart';

/// Karaoke lyrics in the style of Spotify / Apple Music / Riff:
/// the sung line fills with light word by word, the word being sung lifts
/// and glows, nearby lines are softly blurred by distance, and the list
/// glides to follow the song. Tap a line to jump there.
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(track));
    final size = ref.watch(settingsProvider).lyricsSize;
    // Translation loads on its own; lyrics never wait for it.
    final translation = ref.watch(settingsProvider).lyricsTranslate
        ? ref.watch(lyricsTranslationProvider(track)).value
        : null;
    // Its own layer: the word fill repaints every frame, the rest of the
    // player doesn't have to.
    return RepaintBoundary(
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: size),
        child: lyrics.when(
          loading: () => const Center(
            child: SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white70,
              ),
            ),
          ),
          error: (_, _) => const _Message('Не получилось загрузить текст'),
          data: (l) => l == null || l.lines.isEmpty
              ? const _Message('Текст для этого трека не найден')
              : _Lines(
                  lyrics: l,
                  translation: translation?.length == l.lines.length
                      ? translation
                      : null,
                ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 16,
      ),
    ),
  );
}

/// Size comes from settings via DefaultTextStyle (see [LyricsView]).
const _lineStyle = TextStyle(
  height: 1.22,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.5,
  color: Colors.white,
);

class _Lines extends ConsumerStatefulWidget {
  const _Lines({required this.lyrics, this.translation});

  final Lyrics lyrics;

  /// One translated string per line, when translation is on and ready.
  final List<String>? translation;

  @override
  ConsumerState<_Lines> createState() => _LinesState();
}

class _LinesState extends ConsumerState<_Lines>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys = _makeKeys();

  /// Position interpolated every frame: the player only reports a few times
  /// a second, which would make the word fill step instead of flow.
  final _smooth = ValueNotifier(Duration.zero);
  late final Ticker _ticker;
  Duration _basePos = Duration.zero;
  final _sinceBase = Stopwatch();
  bool _playing = false;

  int _index = -2;
  DateTime _manualUntil = DateTime(0);

  /// User's lyrics shift from settings (+ later, − earlier).
  int _offsetMs = 0;

  List<GlobalKey> _makeKeys() =>
      List.generate(widget.lyrics.lines.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _basePos = ref.read(positionProvider).value ?? Duration.zero;
    _sinceBase.start();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration _) {
    final pos = _playing ? _basePos + _sinceBase.elapsed : _basePos;
    // Reading lags behind hearing: light a word a touch early.
    final shown = pos + Duration(milliseconds: 150 + _offsetMs);
    _smooth.value = shown;
    final i = widget.lyrics.lineAt(shown);
    if (i != _index) {
      setState(() => _index = i);
      _follow(i);
    }
  }

  @override
  void didUpdateWidget(_Lines old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _keys = _makeKeys();
      _index = -2;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    _smooth.dispose();
    super.dispose();
  }

  void _follow(int index) {
    if (index < 0 || DateTime.now().isBefore(_manualUntil)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[index].currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutQuart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Re-anchor the interpolation whenever the player reports.
    ref.listen(positionProvider, (_, next) {
      final p = next.value;
      if (p == null) return;
      _basePos = p;
      _sinceBase
        ..reset()
        ..start();
    });
    _playing = ref.watch(playingProvider).value ?? false;
    final settings = ref.watch(settingsProvider);
    _offsetMs = settings.lyricsOffsetMs;

    final lyrics = widget.lyrics;
    final player = ref.read(playerProvider);

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _manualUntil = DateTime.now().add(const Duration(seconds: 3));
        return false;
      },
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.14, 0.82, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          // All lines are built (a song is ~100 lines), so any line can be
          // scrolled to.
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in lyrics.lines.indexed)
                  KeyedSubtree(
                    key: _keys[i],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: lyrics.synced
                          ? () => player.seek(line.time)
                          : null,
                      child: _Line(
                        lyrics: lyrics,
                        index: i,
                        current: _index,
                        position: _smooth,
                        settings: settings,
                        translation: widget.translation?[i],
                      ),
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

class _Line extends StatelessWidget {
  const _Line({
    required this.lyrics,
    required this.index,
    required this.current,
    required this.position,
    required this.settings,
    this.translation,
  });

  final Lyrics lyrics;
  final int index;
  final int current;
  final ValueListenable<Duration> position;
  final AppSettings settings;
  final String? translation;

  /// The line with its translation in small type underneath.
  Widget _withTranslation(BuildContext context, Widget line, bool center) {
    final t = translation;
    if (t == null || t.isEmpty || t == lyrics.lines[index].text) return line;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        const SizedBox(height: 4),
        Text(
          t,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: _size(context) * 0.56,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = lyrics.lines[index].text;
    final center = settings.lyricsAlign == LyricsAlign.center;
    final align = center ? TextAlign.center : TextAlign.start;
    if (!lyrics.synced) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _withTranslation(
          context,
          Text(
            text,
            textAlign: align,
            style: _lineStyle.copyWith(
              fontSize: _size(context) * 0.8,
              color: Colors.white70,
            ),
          ),
          center,
        ),
      );
    }

    final isCurrent = index == current;
    final distance = (index - current).abs();
    // Further lines: dimmer and softer, like depth of field.
    // Blurring each line is too heavy for many Android phones.
    final blur = isCurrent || !settings.lyricsBlur || lightEffects
        ? 0.0
        : math.min(distance * 0.8, 2.6);
    final opacity = isCurrent ? 1.0 : (index < current ? 0.3 : 0.48);

    final Widget content = text.isEmpty
        ? _Dots(active: isCurrent, center: center)
        : _withTranslation(
            context,
            isCurrent
                ? ValueListenableBuilder<Duration>(
                    valueListenable: position,
                    builder: (_, pos, _) => _SungLine(
                      words: lyrics.wordsOf(index),
                      lineStart: lyrics.lines[index].time,
                      position: pos,
                      settings: settings,
                    ),
                  )
                : Text(text, textAlign: align, style: _lineStyle),
            center,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: blur),
        duration: const Duration(milliseconds: 500),
        curve: SegueMotion.ease,
        builder: (context, b, child) => b < 0.05
            ? child!
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: b, sigmaY: b),
                child: child,
              ),
        child: AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 450),
          child: _Wheel(
            // 3D: lines above and below the current one curve away, like
            // the surface of a turning drum.
            angle: settings.depth3d && current >= 0
                ? (index - current).clamp(-6, 6) * -0.045
                : 0,
            // Pivot on the line's centre: pivoting on the left edge shears
            // the text into a fake italic.
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: isCurrent ? 1.0 : 0.93,
              alignment: center ? Alignment.center : Alignment.centerLeft,
              duration: const Duration(milliseconds: 650),
              curve: SegueMotion.spring,
              child: SizedBox(width: double.infinity, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.angle,
    required this.alignment,
    required this.child,
  });

  final double angle;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: angle),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, a, child) => a.abs() < 0.001
          ? child!
          : Transform(
              alignment: alignment,
              transform: perspective(x: a, depth: 0.0016),
              child: child,
            ),
      child: child,
    );
  }
}

/// The line being sung, lit according to the chosen style.
class _SungLine extends StatelessWidget {
  const _SungLine({
    required this.words,
    required this.lineStart,
    required this.position,
    required this.settings,
  });

  final List<LyricWord> words;
  final Duration lineStart;
  final Duration position;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final size = _size(context);
    // "Line" style: everything lights together, fading in over 300 ms.
    final lineProgress = ((position - lineStart).inMilliseconds / 300).clamp(
      0.0,
      1.0,
    );
    return Wrap(
      spacing: size * 0.26,
      alignment: settings.lyricsAlign == LyricsAlign.center
          ? WrapAlignment.center
          : WrapAlignment.start,
      children: [
        for (final w in words)
          _Word(
            text: w.text,
            progress: settings.lyricsStyle == LyricsStyle.line
                ? lineProgress
                : w.progressAt(position),
            settings: settings,
          ),
      ],
    );
  }
}

class _Word extends StatelessWidget {
  const _Word({
    required this.text,
    required this.progress,
    required this.settings,
  });

  final String text;
  final double progress;
  final AppSettings settings;

  static const _edge = 0.2; // soft edge of the light sweep
  static const _dimAlpha = 0.34;

  @override
  Widget build(BuildContext context) {
    final style = settings.lyricsStyle;
    final singing = progress > 0 && progress < 1;
    final lift = settings.lyricsLift && singing && style != LyricsStyle.line
        ? math.sin(progress * math.pi)
        : 0.0;

    // Text painted with a horizontal mask: bright where sung, dim after.
    Widget masked(double alphaScale) {
      final dim = Colors.white.withValues(alpha: _dimAlpha * alphaScale);
      final lit = Colors.white.withValues(alpha: alphaScale);
      if (style == LyricsStyle.sweep) {
        final p = -_edge + progress * (1 + 2 * _edge);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [lit, lit, dim, dim],
            stops: [
              0,
              (p - _edge).clamp(0.0, 1.0),
              (p + _edge).clamp(0.0, 1.0),
              1,
            ],
          ).createShader(rect),
          child: Text(text, style: _lineStyle),
        );
      }
      // pop / line: the whole word fades from dim to lit.
      final t = style == LyricsStyle.pop
          ? (progress * 3).clamp(0.0, 1.0)
          : progress;
      return Text(
        text,
        style: _lineStyle.copyWith(color: Color.lerp(dim, lit, t)),
      );
    }

    // Pop style: a quick scale bump when the word starts.
    final pop = style == LyricsStyle.pop && singing
        ? 1 + 0.08 * math.sin((progress * 3).clamp(0.0, 1.0) * math.pi)
        : 1.0;

    final glow = settings.lyricsGlow * (progress > 0 ? 1 : 0);
    return Transform.translate(
      offset: Offset(0, -3 * lift),
      child: Transform.scale(
        scale: pop,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Glow: a blurred copy of the lit part, behind the text. (A text
            // shadow inside the mask would light up a rectangle instead.)
            if (glow > 0.02)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 6 + 6 * lift,
                    sigmaY: 6 + 6 * lift,
                  ),
                  child: Opacity(
                    opacity: (glow * (0.55 + 0.45 * lift)).clamp(0.0, 1.0),
                    child: masked(1),
                  ),
                ),
              ),
            masked(1),
          ],
        ),
      ),
    );
  }
}

/// Instrumental gap: three dots that breathe while it's the current "line".
class _Dots extends StatefulWidget {
  const _Dots({required this.active, this.center = false});

  final bool active;
  final bool center;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size(context) * 1.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisAlignment: widget.center
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(
                    alpha: widget.active
                        ? 0.35 +
                              0.65 *
                                  (0.5 +
                                      0.5 *
                                          math.sin(
                                            (_c.value - i * 0.18) * 2 * math.pi,
                                          ))
                        : 0.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

double _size(BuildContext context) =>
    DefaultTextStyle.of(context).style.fontSize ?? 28;

/// A sample line sung on a loop with the given settings (settings screen).
class LyricsPreview extends StatefulWidget {
  const LyricsPreview({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<LyricsPreview> createState() => _LyricsPreviewState();
}

class _LyricsPreviewState extends State<LyricsPreview>
    with SingleTickerProviderStateMixin {
  static final _lyrics = Lyrics.parseLrc(
    '[00:00.00]Я слышу эту песню\n[00:03.20]И она звучит везде\n[00:06.40]Ещё один круг',
  );
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: widget.settings.lyricsSize * 0.8),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pos = Duration(milliseconds: (_c.value * 6400).round());
          final current = _lyrics.lineAt(pos);
          final notifier = ValueNotifier(pos);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 2; i++)
                _Line(
                  lyrics: _lyrics,
                  index: i,
                  current: current,
                  position: notifier,
                  settings: widget.settings,
                ),
            ],
          );
        },
      ),
    );
  }
}
