import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../player/player_handler.dart';

/// Feeds the "living notch" on MacBooks (drawn natively, see
/// macos/Runner/MainFlutterWindow.swift) and takes its button presses.
class NotchBridge {
  NotchBridge(this.player);

  final SegueAudioHandler player;
  static const _channel = MethodChannel('fm.segue/notch');

  static bool get supported => Platform.isMacOS;

  Color _accent = const Color(0xFFFF9A76);
  Timer? _debounce;

  void attach() {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
      switch (call.arguments) {
        case 'toggle':
          player.playbackState.value.playing ? player.pause() : player.play();
        case 'next':
          player.skipToNext();
        case 'prev':
          player.skipToPrevious();
      }
    });
    player.stateChanges.listen((_) => _schedule());
    player.mediaItem.listen((_) => _schedule());
  }

  set accent(Color c) {
    if (c == _accent) return;
    _accent = c;
    _schedule();
  }

  Future<void> setEnabled(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('enabled', {'value': on});
    } catch (e) {
      debugPrint('notch: $e');
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _send);
  }

  Future<void> _send() async {
    final item = player.mediaItem.value;
    final snap = player.snapshot();
    try {
      await _channel.invokeMethod('update', {
        'title': item?.title ?? '',
        'artist': item?.artist ?? '',
        'artwork': item?.artUri?.toString() ?? '',
        'playing': snap['playing'] == true,
        'position': ((snap['positionMs'] as int?) ?? 0) / 1000.0,
        'duration': (item?.duration?.inMilliseconds ?? 0) / 1000.0,
        'accent': _accent.toARGB32() & 0xFFFFFF,
      });
    } catch (e) {
      debugPrint('notch: $e');
    }
  }
}
