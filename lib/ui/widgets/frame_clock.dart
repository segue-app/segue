import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// One shared 30 fps beat for all decorative motion. Everything that moves
/// slowly (clouds, waves, bars, a breathing logo) updates on the same
/// beat, so the window is redrawn 30 times a second in total, not 30 per
/// animation with each one's timer slightly apart.
class Beat {
  Beat._();

  static const interval = Duration(microseconds: 33333);
  static final _listeners = <VoidCallback>[];
  static Timer? _timer;

  static void add(VoidCallback f) {
    _listeners.add(f);
    _timer ??= Timer.periodic(interval, (_) {
      for (final l in List.of(_listeners)) {
        l();
      }
      if (_listeners.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  static void remove(VoidCallback f) => _listeners.remove(f);
}

/// A slow animation clock for decorative motion (drifting colours, waves).
///
/// A [Ticker] asks for a frame on every display refresh, 120 times a
/// second on ProMotion screens and many phones, even when the picture
/// barely changes. This one runs on the shared [Beat] at up to [fps]
/// frames a second. It holds still while its route is covered
/// ([TickerMode]) or the app is hidden.
class FrameClock {
  FrameClock(this.onFrame);

  /// Seconds since the last call (at most 0.1).
  final void Function(double dt) onFrame;

  int _fps = 0;
  bool _on = false;
  final _since = Stopwatch();
  ValueListenable<TickerModeData>? _mode;

  bool get running => _on;

  /// Call from didChangeDependencies: follows the route's TickerMode.
  void bind(BuildContext context) =>
      _mode = TickerMode.getValuesNotifier(context);

  void start(int fps) {
    _fps = fps;
    if (_on) return;
    _on = true;
    _since
      ..reset()
      ..start();
    Beat.add(_beat);
  }

  void _beat() {
    final elapsed = _since.elapsedMicroseconds;
    // Slower clocks skip beats (a little slack for timer jitter).
    if (elapsed < 1000000 ~/ _fps - 4000) return;
    _since
      ..reset()
      ..start();
    if (_mode?.value.enabled == false) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life == AppLifecycleState.hidden || life == AppLifecycleState.paused) {
      return;
    }
    onFrame((elapsed / 1e6).clamp(0.0, 0.1));
  }

  void stop() {
    if (!_on) return;
    _on = false;
    Beat.remove(_beat);
  }
}
