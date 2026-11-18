import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../player/player_handler.dart';

/// Windows' own media controls (System Media Transport Controls): the
/// overlay by the volume flyout and on the lock screen with the song,
/// its cover and buttons, and the keyboard's media keys, which Windows
/// routes there. audio_service, which does this elsewhere, has no
/// Windows side.
class WindowsMedia {
  SMTCWindows? _smtc;
  Timer? _tick;

  static bool get supported => Platform.isWindows;

  /// Once, before the window is up (loads the native part).
  static Future<void> init() async {
    if (!supported) return;
    try {
      await SMTCWindows.initialize();
    } catch (e) {
      debugPrint('smtc: $e');
    }
  }

  void attach(SegueAudioHandler player) {
    if (!supported) return;
    final SMTCWindows smtc;
    try {
      smtc = _smtc = SMTCWindows(
        enabled: false,
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: false,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );
    } catch (e) {
      debugPrint('smtc: $e');
      return;
    }

    smtc.buttonPressStream.listen((b) {
      switch (b) {
        case PressedButton.play:
          player.play();
        case PressedButton.pause:
          player.pause();
        case PressedButton.next:
          player.skipToNext();
        case PressedButton.previous:
          player.skipToPrevious();
        case PressedButton.stop:
          player.pause();
        default:
          break;
      }
    });

    player.mediaItem.listen((item) => _show(item));
    player.playbackState.map((s) => s.playing).distinct().listen((playing) {
      _guard(
        () => smtc.setPlaybackStatus(
          playing ? PlaybackStatus.playing : PlaybackStatus.paused,
        ),
      );
      _timeline(player);
    });
    // Where in the song: on changes, and now and then while it plays (the
    // overlay's bar doesn't move on its own).
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.playbackState.value.playing) _timeline(player);
    });
  }

  Future<void> _show(MediaItem? item) async {
    final smtc = _smtc;
    if (smtc == null) return;
    if (item == null) {
      await _guard(smtc.disableSmtc);
      return;
    }
    await _guard(smtc.enableSmtc);
    await _guard(
      () => smtc.updateMetadata(
        MusicMetadata(
          title: item.title,
          artist: item.artist ?? '',
          album: item.album ?? '',
          albumArtist: item.artist ?? '',
          thumbnail: thumbnailFor(item.artUri),
        ),
      ),
    );
  }

  void _timeline(SegueAudioHandler player) {
    final smtc = _smtc;
    final length = player.mediaItem.value?.duration;
    if (smtc == null || length == null) return;
    final st = player.playbackState.value;
    final pos = st.playing
        ? st.updatePosition +
              DateTime.now().difference(st.updateTime) * st.speed
        : st.updatePosition;
    final ms = length.inMilliseconds;
    _guard(
      () => smtc.updateTimeline(
        PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: ms,
          positionMs: pos.inMilliseconds.clamp(0, ms),
          minSeekTimeMs: 0,
          maxSeekTimeMs: ms,
        ),
      ),
    );
  }

  /// A cover Windows can open: a web address or a file:// URI. Anything
  /// else stays out (the native side gives up on an address it can't
  /// parse).
  @visibleForTesting
  static String? thumbnailFor(Uri? art) {
    if (art == null) return null;
    if (art.scheme == 'http' || art.scheme == 'https') return art.toString();
    if (art.scheme == 'file') return art.toString();
    return null;
  }

  static Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('smtc: $e');
    }
  }

  void dispose() {
    _tick?.cancel();
    _smtc?.dispose();
  }
}
