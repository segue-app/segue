import 'dart:io';

import 'package:flutter/services.dart';

/// "Ok Google, play … on Segue" through the Android activity
/// (MEDIA_PLAY_FROM_SEARCH): the assistant opens Segue with the words
/// said, including when it was closed. The media session's own
/// playFromSearch covers the case where Segue is already playing.
class VoiceIntent {
  static const _ch = MethodChannel('fm.segue/voice');

  /// Plays every request, the one that started the app included.
  static Future<void> listen(Future<void> Function(String query) play) async {
    if (!Platform.isAndroid) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'play') await play(call.arguments as String? ?? '');
    });
    try {
      final q = await _ch.invokeMethod<String>('take');
      if (q != null) await play(q);
    } on PlatformException {
      // An older activity without the channel: nothing was asked.
    } on MissingPluginException {
      // Same, in tests and on the other platforms.
    }
  }
}
