import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'slow_ticker.dart';

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
    with SlowTickerProviderStateMixin {
  // Moves only while the music plays: a still wave costs nothing.
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _phase.repeat();
  }

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
    final p = _pending;
    if (p != null && (widget.progress - p).abs() < 0.015) _pending = null;
    if (old.playing != widget.playing) {
      if (widget.playing) {
        if (!_phase.isAnimating) _phase.repeat();
        _amplitude.animateTo(1, curve: SegueMotion.ease);
      } else {
        // Flatten, then stop the wave altogether.
        _amplitude.animateTo(0, curve: SegueMotion.ease).whenCompleteOrCancel(
          () {
            if (mounted && !widget.playing) _phase.stop();
          },
        );
      }
    }
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _phase.dispose();
    _amplitude.dispose();
    super.dispose();
  }

  double _fraction(Offset local, double width) =>
      (local.dx / width).clamp(0.0, 1.0);

  /// Where the user just seeked to: shown until the player gets there, so
  /// the handle doesn't jump back while the new position loads.
  double? _pending;
  Timer? _pendingTimer;

  void _seek(double f) {
    widget.onSeek?.call(f);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pending = null);
    });
    setState(() {
      _pending = f;
      _drag = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Follow the finger from the first touch, not after the drag
          // threshold.
          onHorizontalDragDown: (d) =>
              setState(() => _drag = _fraction(d.localPosition, width)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = _fraction(d.localPosition, width)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) _seek(_drag!);
          },
          onHorizontalDragCancel: () {
            // A tap: seek where it landed.
            if (_drag != null) _seek(_drag!);
          },
          child: SizedBox(
            height: 32,
            width: width,
            child: AnimatedBuilder(
              animation: Listenable.merge([_phase, _amplitude]),
              builder: (context, _) => CustomPaint(
                painter: _WavePainter(
                  progress: _drag ?? _pending ?? widget.progress,
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

/// Thin progress line you can drag to seek (compact mini player).
class SeekLine extends StatefulWidget {
  const SeekLine({
    super.key,
    required this.progress,
    required this.color,
    this.onSeek,
  });

  final double progress;
  final Color color;
  final ValueChanged<double>? onSeek;

  @override
  State<SeekLine> createState() => _SeekLineState();
}

class _SeekLineState extends State<SeekLine> {
  double? _drag;
  double? _pending;
  Timer? _pendingTimer;

  @override
  void didUpdateWidget(SeekLine old) {
    super.didUpdateWidget(old);
    final p = _pending;
    if (p != null && (widget.progress - p).abs() < 0.015) _pending = null;
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _seek(double f) {
    widget.onSeek?.call(f);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pending = null);
    });
    setState(() {
      _pending = f;
      _drag = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      double at(Offset p) => (p.dx / c.maxWidth).clamp(0.0, 1.0);
      final v = _drag ?? _pending ?? widget.progress;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragDown: widget.onSeek == null
            ? null
            : (d) => setState(() => _drag = at(d.localPosition)),
        onHorizontalDragUpdate: widget.onSeek == null
            ? null
            : (d) => setState(() => _drag = at(d.localPosition)),
        onHorizontalDragEnd: (_) {
          if (_drag != null) _seek(_drag!);
        },
        onHorizontalDragCancel: () => setState(() => _drag = null),
        // A tap on the line seeks there (the rest of the mini player
        // still opens the full one).
        onTapUp: widget.onSeek == null
            ? null
            : (d) => _seek(at(d.localPosition)),
        // A finger-sized touch area around the thin line.
        child: SizedBox(
          height: 26,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: _drag != null ? 6 : 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: widget.color,
                  ),
                ),
              ),
              // A handle that says "drag me"; it grows under the finger.
              if (widget.onSeek != null)
                AnimatedPositioned(
                  // Under the finger it follows at once, no lag.
                  duration: _drag != null
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  left: (c.maxWidth * v - (_drag != null ? 8 : 5)).clamp(
                    0.0,
                    c.maxWidth - (_drag != null ? 16 : 10),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _drag != null ? 16 : 10,
                    height: _drag != null ? 16 : 10,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
