import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings/settings.dart';
import '../theme/theme.dart';
import 'frame_clock.dart';

/// Animated background built from the cover's colours (not the image):
/// soft colour clouds drift, swirl and breathe over a deep base, like a
/// living mesh gradient. Flows while music plays, glides to a stop on
/// pause, and blends smoothly into the next track's colours.
class LivingBackdrop extends StatefulWidget {
  const LivingBackdrop({
    super.key,
    required this.palette,
    required this.base,
    required this.playing,
    this.speed = 1,
    this.intensity = 1,
    this.style = BackdropStyle.living,
  });

  /// Cover colours, most prominent first (4 expected).
  final List<Color> palette;

  /// Deep base tone under the clouds.
  final Color base;
  final bool playing;

  /// Motion multiplier (0 = still) and cloud brightness, from settings.
  final double speed;
  final double intensity;
  final BackdropStyle style;

  @override
  State<LivingBackdrop> createState() => _LivingBackdropState();
}

class _LivingBackdropState extends State<LivingBackdrop> {
  late final _clock = FrameClock(_tick);

  /// Animation clock (seconds); only advances while playing.
  double _t = math.Random().nextDouble() * 60;
  double _speed = 0;

  /// Colours currently on screen, eased towards the widget's palette.
  late final List<Color> _colors = _normalized(widget.palette);
  late Color _base = widget.base;

  @override
  void initState() {
    super.initState();
    _speed = widget.playing ? 1 : 0;
    _clock.start(_fps);
  }

  /// Clouds drift slowly: 30 frames a second look the same as 120.
  static int get _fps => lightEffects ? 24 : 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.bind(context);
  }

  @override
  void didUpdateWidget(LivingBackdrop old) {
    super.didUpdateWidget(old);
    // Woken by playing again or by a new track's colours.
    if (!_clock.running) _clock.start(_fps);
  }

  static List<Color> _normalized(List<Color> p) =>
      List.generate(4, (i) => p.isEmpty ? Colors.black : p[i % p.length]);

  void _tick(double dt) {
    final targetSpeed = widget.playing ? 1.0 : 0.0;
    _speed += (targetSpeed - _speed) * (dt * 1.8).clamp(0.0, 1.0);

    // Colour easing (~1.5 s to blend into a new track's palette).
    final k = (dt * 2.2).clamp(0.0, 1.0);
    final target = _normalized(widget.palette);
    var colorsMoving = false;
    for (var i = 0; i < 4; i++) {
      final next = Color.lerp(_colors[i], target[i], k)!;
      if (_distance(next, target[i]) > 0.002) colorsMoving = true;
      _colors[i] = next;
    }
    _base = Color.lerp(_base, widget.base, k)!;

    // Fully paused and settled: stop until something changes.
    if (_speed < 0.002 && !colorsMoving && !widget.playing) {
      _repaint.value++;
      _clock.stop();
      return;
    }
    final styleSpeed = switch (widget.style) {
      BackdropStyle.living => 1.0,
      BackdropStyle.calm => 0.35,
      BackdropStyle.plain => 0.0,
    };
    _t += dt * _speed * widget.speed * styleSpeed;
    _repaint.value++;
  }

  /// Repaints only the clouds, never the screen built on top of them.
  final _repaint = ValueNotifier(0);

  static double _distance(Color a, Color b) =>
      (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

  @override
  void dispose() {
    _clock.stop();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CloudsPainter(this, _repaint),
        child: const SizedBox.expand(),
      ),
    );
  }

  double get _intensity => switch (widget.style) {
    BackdropStyle.living => widget.intensity,
    BackdropStyle.calm => widget.intensity * 0.6,
    BackdropStyle.plain => 0,
  };
}

class _CloudsPainter extends CustomPainter {
  _CloudsPainter(this.s, Listenable repaint) : super(repaint: repaint);

  final _LivingBackdropState s;

  double get intensity => s._intensity;
  double get t => s._t;
  List<Color> get colors => s._colors;
  Color get base => s._base;

  // Per cloud: start x, start y (0..1), orbit size, orbit speeds x/y,
  // radius (share of the longest side), phase.
  static const _clouds = [
    (0.20, 0.25, 0.30, 0.130, 0.090, 0.55, 0.0),
    (0.85, 0.30, 0.32, -0.110, 0.140, 0.50, 1.7),
    (0.30, 0.85, 0.30, 0.120, -0.080, 0.60, 3.1),
    (0.80, 0.80, 0.28, -0.090, -0.120, 0.50, 4.6),
    // A fifth, smaller cloud reuses the first colour for extra movement.
    (0.50, 0.50, 0.35, 0.070, 0.150, 0.38, 2.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Darker base than the tint: the clouds read as light moving over it.
    canvas.drawRect(
      rect,
      Paint()..color = Color.lerp(base, const Color(0xFF070708), 0.45)!,
    );

    final longest = math.max(size.width, size.height);
    final a = t * 2 * math.pi;
    for (var i = 0; i < _clouds.length; i++) {
      final (x, y, orbit, sx, sy, r, phase) = _clouds[i];
      final cx = (x + math.sin(a * sx + phase) * orbit) * size.width;
      final cy = (y + math.cos(a * sy + phase * 1.3) * orbit) * size.height;
      // Breathing radius.
      final radius = longest * r * (1 + 0.18 * math.sin(a * 0.2 + phase));
      final color = colors[i % colors.length];
      final center = Offset(cx, cy);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
              color.withValues(alpha: (0.5 * intensity).clamp(0.0, 1.0)),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Bottom shade keeps the title and controls readable.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x26000000), Color(0x4D000000), Color(0xC70B0B0D)],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CloudsPainter old) => old.s != s;
}
