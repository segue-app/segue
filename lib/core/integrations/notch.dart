import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/track.dart';
import '../player/player_handler.dart';

/// Feeds the "living notch" on MacBooks (drawn natively, see
/// macos/Runner/MainFlutterWindow.swift) and acts on what's done there:
/// play/pause, skip, seek, like, volume, open the app.
///
/// When this Mac isn't playing but another of your devices is, the notch
/// shows that device's music and its buttons control it.
class NotchBridge {
  NotchBridge(
    this.player, {
    required this.isLiked,
    required this.toggleLike,
    required this.onOpen,
    required this.setVolume,
  });

  final SegueAudioHandler player;
  final bool Function(Track track) isLiked;
  final void Function(Track track) toggleLike;
  final VoidCallback onOpen;

  final void Function(double volume) setVolume;

  static const _channel = MethodChannel('fm.segue/notch');

  static bool get supported => Platform.isMacOS;

  Color _accent = const Color(0xFFFF9A76);
  Timer? _debounce;

  void attach() {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
      final args = (call.arguments as Map).cast<String, Object?>();
      _command(
        args['op'] as String? ?? '',
        (args['value'] as num?)?.toDouble(),
      );
    });
    player.stateChanges.listen((_) => refresh());
    player.mediaItem.listen((_) => refresh());
    player.playingStream.listen((_) => refresh());
    player.output.addListener(refresh);
  }

  void dispose() {
    _debounce?.cancel();
  }

  set accent(Color c) {
    if (c == _accent) return;
    _accent = c;
    refresh();
  }

  Future<void> setEnabled(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('enabled', {'value': on});
    } catch (e) {
      debugPrint('notch: $e');
    }
  }

  Future<void> setDesktopWidget(bool on) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('desktopWidget', {'value': on});
    } catch (e) {
      debugPrint('desktop widget: $e');
    }
  }

  /// Re-sends what the notch shows (call when likes or remote state change).
  void refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _send);
  }

  void _command(String op, double? value) {
    // The player itself forwards to another device while it's a remote.
    switch (op) {
      case 'toggle':
        player.isPlaying ? player.pause() : player.play();
      case 'next':
        player.skipToNext();
      case 'prev':
        player.skipToPrevious();
      case 'seek':
        player.seek(Duration(milliseconds: ((value ?? 0) * 1000).round()));
      case 'volume':
        setVolume(value ?? 1);
      case 'like':
        final t = player.current;
        if (t != null) toggleLike(t);
        refresh();
      case 'open':
        onOpen();
    }
  }

  Future<void> _send() async {
    final t = player.current;
    final item = player.mediaItem.value;
    try {
      await _channel.invokeMethod('update', {
        'title': item?.title ?? '',
        'artist': item?.artist ?? '',
        'artwork': item?.artUri?.toString() ?? '',
        'playing': player.isPlaying,
        'position': player.position.inMilliseconds / 1000,
        'duration': (item?.duration?.inMilliseconds ?? 0) / 1000,
        'accent': _accent.toARGB32() & 0xFFFFFF,
        'liked': t != null && isLiked(t),
        'device': player.output.value ?? '',
        // The native side shows these as they are.
        'onDevice': 'на {0}'.trArgs([player.output.value ?? '']),
        'idleText': 'Ничего не играет'.tr,
        'openText': 'Открыть Segue'.tr,
        'volume': player.volume.value,
      });
    } catch (e) {
      debugPrint('notch: $e');
    }
  }
}
