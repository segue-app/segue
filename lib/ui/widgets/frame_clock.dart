import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A slow animation clock for decorative motion (drifting colours, waves).
///
/// A [Ticker] asks for a frame on every display refresh, 120 times a
/// second on ProMotion screens and many phones, even when the picture
/// barely changes. This one fires [fps] times a second, so the engine only
/// draws when there's something new. It holds still while its route is
/// covered ([TickerMode]) or the app is hidden.
class FrameClock {
  FrameClock(this.onFrame);

  /// Seconds since the last call (at most 0.1).
  final void Function(double dt) onFrame;

  Timer? _timer;
  int _fps = 0;
  final _since = Stopwatch();
  ValueListenable<TickerModeData>? _mode;

  bool get running => _timer != null;

  /// Call from didChangeDependencies: follows the route's TickerMode.
  void bind(BuildContext context) =>
      _mode = TickerMode.getValuesNotifier(context);

  void start(int fps) {
    if (_timer != null && _fps == fps) return;
    _timer?.cancel();
    _fps = fps;
    _since
      ..reset()
      ..start();
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ fps), (_) {
      final dt = (_since.elapsedMicroseconds / 1e6).clamp(0.0, 0.1);
      _since
        ..reset()
        ..start();
      if (_mode?.value.enabled == false) return;
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.hidden ||
          life == AppLifecycleState.paused) {
        return;
      }
      onFrame(dt);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
