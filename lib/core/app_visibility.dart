import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the user can see the app, and whether it's the one in front.
///
/// * Not visible (covered, minimised, another Space, phone screen off):
///   nothing animates and the progress refreshes every couple of seconds.
/// * Visible but another app in front: lyrics and progress go on, the
///   ambient decoration (moving backgrounds, dancing bars) holds still.
///
/// On macOS the window reports it; elsewhere the app lifecycle tells.
class AppVisibility {
  AppVisibility._();

  static const _channel = MethodChannel('fm.segue/window');
  static bool? _nativeVisible, _nativeActive;

  /// Changes when [visible] does (the app mutes its animations on it).
  static final visibleNotifier = ValueNotifier<bool>(true);

  static void attach() {
    WidgetsBinding.instance.addObserver(_Observer());
    if (Platform.isMacOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'foreground') {
          final a = (call.arguments as Map).cast<String, Object?>();
          _nativeVisible = a['visible'] == true;
          _nativeActive = a['active'] == true;
          _update();
        }
      });
    }
  }

  static AppLifecycleState? get _life => WidgetsBinding.instance.lifecycleState;

  /// On screen (maybe behind the app being used).
  static bool get visible {
    final n = _nativeVisible;
    if (n != null) return n;
    final life = _life;
    return life == null ||
        life == AppLifecycleState.resumed ||
        life == AppLifecycleState.inactive;
  }

  /// Set by the performance tool: animate as if in front.
  @visibleForTesting
  static bool debugAlwaysActive = false;

  /// On screen and the app in front.
  static bool get active {
    if (debugAlwaysActive) return true;
    final n = _nativeActive;
    if (n != null) return n && visible;
    final life = _life;
    return life == null || life == AppLifecycleState.resumed;
  }

  static void _update() => visibleNotifier.value = visible;
}

class _Observer with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      AppVisibility._update();
}
