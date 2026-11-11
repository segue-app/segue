// Plays a track muted with the notch on, so the notch can be looked at
// (screenshots are taken from outside while this runs).
import 'package:flutter/services.dart';
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
    final liked = <String>{};
    final notch =
        NotchBridge(
            player,
            isLiked: (t) => liked.contains(t.key),
            toggleLike: (t) => liked.add(t.key),
            onOpen: () {},
            remote: () => null,
            remoteCommand: (_, _, [_]) {},
            setVolume: (_) {},
          )
          ..attach()
          ..accent = const Color(0xFFFF6B8A);
    await notch.setEnabled(true);
    final tracks = await yt.search('miyagi marlboro', limit: 1);
    liked.add(tracks.first.key);
    await player.playList(tracks, 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(milliseconds: 300))
        .timeout(const Duration(seconds: 40));
    // Jump to where the singing is, then hold the island open.
    await player.seek(const Duration(seconds: 40));
    await Future<void>.delayed(const Duration(seconds: 4));
    await const MethodChannel('fm.segue/notch')
        .invokeMethod('expand', {'value': true});
    // ignore: avoid_print
    print('NOTCH OPEN');
    await Future<void>.delayed(const Duration(seconds: 6));
    await const MethodChannel('fm.segue/notch')
        .invokeMethod('expand', {'value': false});
    // Paused for a while: the notch steps back.
    await player.pause();
    await Future<void>.delayed(const Duration(seconds: 3));
    // ignore: avoid_print
    print('NOTCH PAUSED');
    await Future<void>.delayed(const Duration(seconds: 8));
    // ignore: avoid_print
    print('NOTCH RESTING');
    await Future<void>.delayed(const Duration(seconds: 3));
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
