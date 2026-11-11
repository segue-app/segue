import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Progress bar whose played part is a gentle moving wave while music plays
/// and flattens into a line on pause. Drag or tap to seek.
class WavyProgress extends StatefulWidget {
  const WavyProgress({
    super.key,
    required this.progress,
    required this.playing,
    required this.color,
    this.onSeek,
  });

  /// 0..1
  final double progress;
  final bool playing;
  final Color color;
  final ValueChanged<double>? onSeek;

  @override
  State<WavyProgress> createState() => _WavyProgressState();
}

class _WavyProgressState extends State<WavyProgress>
    with TickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();
  late final _amplitude = AnimationController(
    vsync: this,
    duration: SegueMotion.slow,
    value: widget.playing ? 1 : 0,
  );

  /// Position while the user drags; overrides [widget.progress].
  double? _drag;

  @override
  void didUpdateWidget(WavyProgress old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing
          ? _amplitude.animateTo(1, curve: SegueMotion.ease)
          : _amplitude.animateTo(0, curve: SegueMotion.ease);
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amplitude.dispose();
    super.dispose();
  }

  double _fraction(Offset local, double width) =>
      (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              setState(() => _drag = _fraction(d.localPosition, width)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = _fraction(d.localPosition, width)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) widget.onSeek?.call(_drag!);
            setState(() => _drag = null);
          },
          onTapUp: (d) =>
              widget.onSeek?.call(_fraction(d.localPosition, width)),
          child: SizedBox(
            height: 32,
            width: width,
            child: AnimatedBuilder(
              animation: Listenable.merge([_phase, _amplitude]),
              builder: (context, _) => CustomPaint(
                painter: _WavePainter(
                  progress: _drag ?? widget.progress,
                  phase: _phase.value,
                  amplitude: _amplitude.value,
                  color: widget.color,
                  dragging: _drag != null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.dragging,
  });

  final double progress;
  final double phase;
  final double amplitude;
  final Color color;
  final bool dragging;

  static const _wavelength = 34.0;
  static const _height = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final x = (size.width * progress).clamp(0.0, size.width);
    final stroke = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Remaining part: flat and quiet.
    if (x < size.width - 6) {
      canvas.drawLine(
        Offset(x + 8, midY),
        Offset(size.width, midY),
        stroke..color = Colors.white.withValues(alpha: 0.16),
      );
    }

    // Played part: a sine wave travelling to the right.
    final path = Path()..moveTo(0, midY);
    final amp = _height * amplitude;
    for (double px = 0; px <= x; px += 1.5) {
      // Taper the wave near both ends so it meets the line smoothly.
      final taper = math.min(1.0, math.min(px, x - px) / 14);
      final y =
          midY +
          math.sin((px / _wavelength - phase) * 2 * math.pi) *
              amp *
              taper.clamp(0.0, 1.0);
      path.lineTo(px, y);
    }
    canvas.drawPath(path, stroke..color = color);

    // Handle: a short vertical pill, grows while dragging.
    final handleH = dragging ? 22.0 : 16.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, midY), width: 5, height: handleH),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.amplitude != amplitude ||
      old.color != color ||
      old.dragging != dragging;
}
