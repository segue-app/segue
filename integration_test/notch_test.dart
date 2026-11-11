// Plays a track muted with the notch bridge on, so the notch can be
// looked at (screenshots are taken from outside while this runs).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/integrations/notch.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notch', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    final notch = NotchBridge(player)
      ..attach()
      ..accent = const Color(0xFFFF6B8A);
    await notch.setEnabled(true);
    final tracks = await yt.search('miyagi marlboro', limit: 1);
    await player.playList(tracks, 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(milliseconds: 300))
        .timeout(const Duration(seconds: 40));
    // ignore: avoid_print
    print('NOTCH PLAYING');
    await Future<void>.delayed(const Duration(seconds: 12));
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
