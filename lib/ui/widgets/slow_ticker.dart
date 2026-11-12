import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Use instead of [TickerProviderStateMixin] for looping decoration (a
/// breathing logo, dancing bars, a moving wave). Ordinary tickers draw on
/// every display refresh, up to 120 times a second, and while any one runs
/// the whole window is redrawn that often. These tick [frameInterval]
/// apart (30 fps), which looks the same for slow motion and costs a
/// quarter. They're muted like normal ones when the route is covered.
mixin SlowTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  final _tickers = <_SlowTicker>{};
  ValueListenable<TickerModeData>? _mode;

  Duration get frameInterval => const Duration(microseconds: 33333);

  @override
  Ticker createTicker(TickerCallback onTick) {
    _watchMode();
    final t = _SlowTicker(onTick, frameInterval, this);
    t.muted = !(_mode?.value.enabled ?? true);
    _tickers.add(t);
    return t;
  }

  void _watchMode() {
    final n = TickerMode.getValuesNotifier(context);
    if (identical(n, _mode)) return;
    _mode?.removeListener(_muteAll);
    n.addListener(_muteAll);
    _mode = n;
  }

  void _muteAll() {
    final muted = !(_mode?.value.enabled ?? true);
    for (final t in _tickers) {
      t.muted = muted;
    }
  }

  @override
  void activate() {
    super.activate();
    _watchMode();
    _muteAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tickers.isNotEmpty) {
      _watchMode();
      _muteAll();
    }
  }

  @override
  void dispose() {
    _mode?.removeListener(_muteAll);
    _mode = null;
    super.dispose();
  }
}

class _SlowTicker extends Ticker {
  _SlowTicker(super.onTick, this.interval, this._owner);

  final Duration interval;
  final SlowTickerProviderStateMixin _owner;
  Timer? _wait;

  @override
  void scheduleTick({bool rescheduling = false}) {
    if (!rescheduling) {
      super.scheduleTick();
      return;
    }
    // The next frame, but not before the interval has passed.
    if (_wait != null) return;
    _wait = Timer(interval, () {
      _wait = null;
      if (shouldScheduleTick) super.scheduleTick();
    });
  }

  @override
  void unscheduleTick() {
    _wait?.cancel();
    _wait = null;
    super.unscheduleTick();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _wait = null;
    _owner._tickers.remove(this);
    super.dispose();
  }
}
