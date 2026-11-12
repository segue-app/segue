import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'frame_clock.dart';

/// Artwork of the "Моя волна" card: glowing colour clouds with layered
/// waves rolling through them. Calm while idle; while the wave plays the
/// waves rise, speed up and breathe.
class WaveArt extends StatefulWidget {
  const WaveArt({
    super.key,
    required this.colors,
    required this.playing,
    this.animate = true,
  });

  /// Four vivid colours, deepest first.
  final List<Color> colors;
  final bool playing;

  /// False when animations are switched off in settings.
  final bool animate;

  @override
  State<WaveArt> createState() => _WaveArtState();
}

class _WaveArtState extends State<WaveArt> {
  late final _clock = FrameClock(_tick);
  double _t = 0;

  /// 0 idle … 1 playing, eased so the change is a smooth swell.
  double _energy = 0;
  late List<Color> _colors = List.of(widget.colors);
  final _repaint = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _energy = widget.playing ? 1 : 0;
    if (widget.animate) _clock.start(_fps);
  }

  int get _fps => 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock.bind(context);
  }

  @override
  void didUpdateWidget(WaveArt old) {
    super.didUpdateWidget(old);
    if (widget.animate) {
      _clock.start(_fps);
    } else if (_clock.running) {
      _clock.stop();
      _colors = List.of(widget.colors);
      _energy = widget.playing ? 1 : 0;
      _repaint.value++;
    }
  }

  void _tick(double dt) {
    final target = widget.playing ? 1.0 : 0.0;
    _energy += (target - _energy) * (dt * 1.6).clamp(0.0, 1.0);
    _t += dt * (0.35 + 0.65 * _energy);
    final k = (dt * 2).clamp(0.0, 1.0);
    var settling = _energy > 0.01;
    for (var i = 0; i < _colors.length && i < widget.colors.length; i++) {
      final next = Color.lerp(_colors[i], widget.colors[i], k)!;
      final to = widget.colors[i];
      if ((next.r - to.r).abs() +
              (next.g - to.g).abs() +
              (next.b - to.b).abs() >
          0.004) {
        settling = true;
      }
      _colors[i] = next;
    }
    _repaint.value++;
    // Nothing plays and the swell has died down: a still picture, no
    // more frames until something changes.
    if (!widget.playing && !settling) _clock.stop();
  }

  @override
  void dispose() {
    _clock.stop();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _WavePainter(this, _repaint),
      size: Size.infinite,
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.s, Listenable repaint) : super(repaint: repaint);

  final _WaveArtState s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = s._colors;
    final t = s._t;
    final e = s._energy;
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // Deep base.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(c[0], Colors.black, 0.55)!,
            Color.lerp(c[1], Colors.black, 0.6)!,
          ],
        ).createShader(rect),
    );

    // Drifting colour clouds.
    for (var i = 0; i < 3; i++) {
      final cx =
          w *
          (0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * (0.5 + i * 0.17) + i * 2.1)));
      final cy =
          h * (0.3 + 0.4 * (0.5 + 0.5 * math.cos(t * (0.4 + i * 0.13) + i)));
      final r = math.max(w, h) * (0.45 + 0.1 * math.sin(t * 0.7 + i));
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              c[(i + 1) % c.length].withValues(alpha: 0.55 + 0.15 * e),
              c[(i + 1) % c.length].withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }

    // Rolling waves, back to front.
    const layers = 4;
    for (var l = 0; l < layers; l++) {
      final depth = l / (layers - 1); // 0 back … 1 front
      final baseY = h * (0.42 + 0.14 * depth);
      final amp = h * (0.05 + 0.07 * e) * (1.1 - depth * 0.35);
      final freq = 1.3 + l * 0.35;
      final speed = 0.9 + l * 0.35;
      final path = Path()..moveTo(0, h);
      final crest = Path();
      for (var x = 0.0; x <= w + 4; x += 4) {
        final u = x / w;
        final y =
            baseY +
            amp * math.sin(u * math.pi * 2 * freq + t * speed + l * 1.7) +
            amp *
                0.45 *
                math.sin(u * math.pi * 2 * freq * 2.3 - t * speed * 1.4 + l);
        path.lineTo(x, y);
        if (x == 0) {
          crest.moveTo(x, y);
        } else {
          crest.lineTo(x, y);
        }
      }
      path
        ..lineTo(w, h)
        ..close();
      final color = c[(l + 2) % c.length];
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22 + 0.12 * depth),
              Color.lerp(
                c[0],
                Colors.black,
                0.7,
              )!.withValues(alpha: 0.35 + 0.4 * depth),
            ],
          ).createShader(Rect.fromLTWH(0, baseY - amp * 1.5, w, h - baseY)),
      );
      // Glowing crest line (the glow is skipped where blurs are costly).
      if (!lightEffects) {
        canvas.drawPath(
          crest,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = color.withValues(alpha: 0.25 + 0.25 * e)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Color.lerp(
            color,
            Colors.white,
            0.5,
          )!.withValues(alpha: 0.35 + 0.35 * e),
      );
    }

    // Soft shade on the left so the title stays readable.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.6],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
