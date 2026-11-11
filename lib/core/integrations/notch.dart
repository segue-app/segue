import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../lyrics/lyrics.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import '../sync/relay.dart';

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
    required this.lyricsFor,
    required this.onOpen,
    required this.remote,
    required this.remoteCommand,
    required this.setVolume,
  });

  final SegueAudioHandler player;
  final bool Function(Track track) isLiked;
  final void Function(Track track) toggleLike;
  final Future<Lyrics?> Function(Track track) lyricsFor;
  final VoidCallback onOpen;

  /// The other device playing now, while this one isn't.
  final RemoteDevice? Function() remote;
  final void Function(String id, String op, [Map<String, dynamic>? args])
  remoteCommand;
  final void Function(double volume) setVolume;

  static const _channel = MethodChannel('fm.segue/notch');

  static bool get supported => Platform.isMacOS;

  Color _accent = const Color(0xFFFF9A76);
  Timer? _debounce, _lyricTimer;
  Lyrics? _lyrics;
  String? _lyricsKey;
  String _line = '';

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
    // The sung line moves on between player events.
    _lyricTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _sendLyric(),
    );
  }

  void dispose() {
    _lyricTimer?.cancel();
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

  /// Re-sends what the notch shows (call when likes or remote state change).
  void refresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _send);
  }

  bool get _localPlaying => player.playbackState.value.playing;

  void _command(String op, double? value) {
    final r = _localPlaying ? null : remote();
    if (r != null && r.track != null) {
      // Music on another device: the notch is its remote.
      switch (op) {
        case 'toggle':
          remoteCommand(r.id, r.playing ? 'pause' : 'play');
        case 'next' || 'prev':
          remoteCommand(r.id, op);
        case 'seek':
          remoteCommand(r.id, 'seek', {'ms': ((value ?? 0) * 1000).round()});
        case 'volume':
          remoteCommand(r.id, 'volume', {'v': value ?? 1});
        case 'open':
          onOpen();
      }
      return;
    }
    switch (op) {
      case 'toggle':
        _localPlaying ? player.pause() : player.play();
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

  /// What plays and where: this Mac, or another device while this is idle.
  ({
    Track? track,
    bool playing,
    double position,
    double? duration,
    double volume,
    String device,
  })
  _now() {
    final r = _localPlaying ? null : remote();
    if (r != null && r.track != null) {
      Track? t;
      try {
        t = Track.fromJson(r.track!);
      } catch (_) {}
      return (
        track: t,
        playing: r.playing,
        position: r.position.inMilliseconds / 1000,
        duration: r.duration == null ? null : r.duration!.inMilliseconds / 1000,
        volume: r.volume,
        device: r.name,
      );
    }
    final snap = player.snapshot();
    return (
      track: player.current,
      playing: snap['playing'] == true,
      position: ((snap['positionMs'] as int?) ?? 0) / 1000,
      duration: player.mediaItem.value?.duration == null
          ? null
          : player.mediaItem.value!.duration!.inMilliseconds / 1000,
      volume: player.volume.value,
      device: '',
    );
  }

  Future<void> _send() async {
    final now = _now();
    final t = now.track;
    try {
      await _channel.invokeMethod('update', {
        'title': t?.title ?? '',
        'artist': t?.artist ?? '',
        'artwork': now.device.isEmpty
            ? player.mediaItem.value?.artUri?.toString() ?? t?.artworkUrl ?? ''
            : t?.artworkUrl ?? '',
        'playing': now.playing,
        'position': now.position,
        'duration': now.duration ?? 0,
        'accent': _accent.toARGB32() & 0xFFFFFF,
        'liked': t != null && isLiked(t),
        'device': now.device,
        'volume': now.volume,
      });
    } catch (e) {
      debugPrint('notch: $e');
    }
    _loadLyrics(t);
  }

  void _loadLyrics(Track? t) {
    final key = t?.key;
    if (key == _lyricsKey) return;
    _lyricsKey = key;
    _lyrics = null;
    if (t == null) return;
    lyricsFor(t)
        .then((l) {
          if (_lyricsKey == key) _lyrics = l;
        })
        .catchError((Object _) {});
  }

  Future<void> _sendLyric() async {
    final l = _lyrics;
    var line = '';
    if (l != null && l.synced) {
      final now = _now();
      // A touch early, like the lyrics view: reading lags behind hearing.
      final i = l.lineAt(
        Duration(milliseconds: (now.position * 1000).round() + 150),
      );
      if (i >= 0) line = l.lines[i].text.trim();
    }
    if (line == _line) return;
    _line = line;
    try {
      await _channel.invokeMethod('lyric', {'line': line});
    } catch (_) {}
  }
}
