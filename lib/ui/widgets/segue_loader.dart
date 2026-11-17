import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The loading indicator, drawn from Segue's mark (assets/brand/
/// make_logo.py): a stroke runs down the S — the solid ribbon of the upper
/// half, then the three strands it unravels into, inner one longest — and
/// is followed by its tail, over a faint copy of the whole mark. One song
/// flowing into the next.
///
/// With reduced motion it shows the mark still, breathing slowly.
class SegueLoader extends StatefulWidget {
  const SegueLoader({super.key, this.size = 44, this.color});

  /// Height of the mark; it is narrower than tall.
  final double size;

  /// Paints in one color instead of the brand gradient (over artwork).
  final Color? color;

  @override
  State<SegueLoader> createState() => _SegueLoaderState();
}

class _SegueLoaderState extends State<SegueLoader>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _c.duration = const Duration(milliseconds: 2400);
      _c.repeat(reverse: true);
    } else {
      _c.duration = const Duration(milliseconds: 1900);
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size * _Mark.aspect,
          height: widget.size,
          child: CustomPaint(
            painter: _MarkPainter(_c, still: _still, color: widget.color),
          ),
        ),
      ),
    );
  }
}

/// The mark's geometry, in make_logo.py's 1024 × 1024 space.
abstract final class _Mark {
  static const cx = 512.0;
  static const top = 400.0, bot = 624.0; // the two halves' centres
  static const ribbonR = 112.0, ribbonW = 84.0;
  static const strandW = 24.0;
  static const strandR = [82.0, 112.0, 142.0];
  static const strandEnd = [168.0, 150.0, 128.0]; // degrees
  static const strandStart = -90.5;
  static const ribbonFrom = -30.0, ribbonTo = -270.0;

  // Bounding box of the drawn mark.
  static const left = 358.0, right = 666.0, minY = 246.0, maxY = 778.0;
  static const aspect = (right - left) / (maxY - minY);
  // Room for anti-aliasing at the edges of a layer.
  static const bounds = Rect.fromLTRB(left - 4, minY - 4, right + 4, maxY + 4);

  static const gradient = [
    Color(0xFFFFB86B),
    Color(0xFFFF5E8A),
    Color(0xFF7B5CFF),
  ];
  static const stops = [0.0, 0.42, 1.0];
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, {required this.still, this.color}) : super(repaint: t);

  final Animation<double> t;
  final bool still;
  final Color? color;

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / (_Mark.maxY - _Mark.minY);
    canvas.save();
    canvas.scale(s);
    canvas.translate(-_Mark.left, -_Mark.minY);
    // A translucent color is applied once, to the whole mark: drawn per
    // part, the overlapping caps would show through brighter.
    final faded = color != null && color!.a < 1;
    if (faded) {
      canvas.saveLayer(
        _Mark.bounds,
        Paint()..color = Color.fromRGBO(255, 255, 255, color!.a),
      );
    }

    Paint ink(double opacity, double width) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt
        ..isAntiAlias = true;
      if (color != null) {
        p.color = color!.withValues(alpha: opacity); // see the layer above
      } else {
        // The SVG's gradient line, in the same space as the paths.
        p.shader = ui.Gradient.linear(
          const Offset(380, 270),
          const Offset(640, 780),
          [for (final c in _Mark.gradient) c.withValues(alpha: opacity)],
          _Mark.stops,
        );
      }
      return p;
    }

    if (still) {
      // Reduced motion: the whole mark, breathing.
      final o = 0.55 + 0.45 * Curves.easeInOut.transform(t.value);
      canvas.saveLayer(
        _Mark.bounds,
        Paint()..color = Colors.white.withValues(alpha: o),
      );
      _draw(canvas, ink, 1, 0, 1);
      canvas.restore();
    } else {
      // The ghost, faded as a whole: its caps overlap the arcs.
      canvas.saveLayer(_Mark.bounds, Paint()..color = const Color(0x24FFFFFF));
      _draw(canvas, ink, 1, 0, 1);
      canvas.restore();
      final v = t.value;
      // Head leads, tail follows; both ease so the stroke gathers at the
      // top and lets go at the strands' ends.
      final head = Curves.easeInOutCubic.transform((v / 0.62).clamp(0.0, 1.0));
      final tail = Curves.easeInOutCubic.transform(
        ((v - 0.30) / 0.66).clamp(0.0, 1.0),
      );
      if (head > tail) _draw(canvas, ink, 1, tail, head);
    }
    if (faded) canvas.restore();
    canvas.restore();
  }

  /// Draws the part of the mark between [from] and [to] along it: the
  /// ribbon is 0…0.5, the strands 0.5…1 (all at the same angular speed, so
  /// the shorter outer ones finish first).
  void _draw(
    Canvas canvas,
    Paint Function(double opacity, double width) ink,
    double opacity,
    double from,
    double to,
  ) {
    const split = 0.5;
    // Ribbon: from its round head over the top to the split.
    final r0 = (from / split).clamp(0.0, 1.0);
    final r1 = (to / split).clamp(0.0, 1.0);
    if (r1 > r0) {
      final paint = ink(opacity, _Mark.ribbonW);
      const span = _Mark.ribbonTo - _Mark.ribbonFrom; // negative: CCW
      final a0 = _Mark.ribbonFrom + span * r0;
      final a1 = _Mark.ribbonFrom + span * r1;
      final rect = Rect.fromCircle(
        center: const Offset(_Mark.cx, _Mark.top),
        radius: _Mark.ribbonR,
      );
      canvas.drawArc(rect, _rad(a0), _rad(a1 - a0), false, paint);
      // Round ends everywhere but at the split, where the strands go on.
      final dot = Paint()
        ..shader = paint.shader
        ..color = paint.color;
      dot.style = PaintingStyle.fill;
      for (final (a, at) in [(a0, r0), (a1, r1)]) {
        if (at >= 1) continue;
        canvas.drawCircle(
          _on(_Mark.top, _Mark.ribbonR, a),
          _Mark.ribbonW / 2,
          dot,
        );
      }
    }
    // Strands.
    final u0 = ((from - split) / (1 - split)).clamp(0.0, 1.0);
    final u1 = ((to - split) / (1 - split)).clamp(0.0, 1.0);
    if (u1 <= u0) return;
    final longest = _Mark.strandEnd.reduce(math.max) - _Mark.strandStart;
    final paint = ink(opacity, _Mark.strandW);
    final dot = Paint()
      ..shader = paint.shader
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      final r = _Mark.strandR[i];
      final end = _Mark.strandEnd[i];
      final a0 = math.min(_Mark.strandStart + longest * u0, end);
      final a1 = math.min(_Mark.strandStart + longest * u1, end);
      if (a1 <= a0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(_Mark.cx, _Mark.bot), radius: r),
        _rad(a0),
        _rad(a1 - a0),
        false,
        paint,
      );
      if (u0 > 0) {
        canvas.drawCircle(_on(_Mark.bot, r, a0), _Mark.strandW / 2, dot);
      }
      canvas.drawCircle(_on(_Mark.bot, r, a1), _Mark.strandW / 2, dot);
    }
  }

  static Offset _on(double cy, double r, double deg) =>
      Offset(_Mark.cx + r * math.cos(_rad(deg)), cy + r * math.sin(_rad(deg)));

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.still != still || old.color != color;
}
