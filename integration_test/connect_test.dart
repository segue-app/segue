// A "phone" hands its music over to this Mac's real player (muted),
// through the internet relay.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/youtube_source.dart';
import 'package:segue/core/sync/relay.dart';

import '../test/support/fake_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone hands off to the Mac', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final mac = SegueAudioHandler({SourceKind.youtube: yt});
    await mac.setVolume(0); // silent
    final track = (await yt.search('miyagi marlboro', limit: 1)).first;
    final phone = FakePlayer()
      ..state = {
        'queue': [track.toJson()],
        'index': 0,
        'positionMs': 40000,
        'playing': true,
        'volume': 1.0,
        'durationMs': 240000,
      };
    final macLib = LibraryStore.memory(), phoneLib = LibraryStore.memory();
    final a = Relay(library: macLib, player: mac, deviceName: () => 'Mac');
    final b = Relay(
      library: phoneLib,
      player: phone,
      deviceName: () => 'Phone',
    );
    await a.start();
    await b.start();
    await b.join(await a.openInvite());
    for (
      var i = 0;
      i < 50 && b.devices.value[macLib.deviceId]?.online != true;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final sw = Stopwatch()..start();
    await b.handOffTo(macLib.deviceId);
    final pos = await mac.positionStream
        .firstWhere((p) => p > const Duration(seconds: 41))
        .timeout(const Duration(seconds: 30));
    // ignore: avoid_print
    print(
      'HANDOFF playing on Mac at ${pos.inSeconds}s after ${sw.elapsedMilliseconds}ms',
    );
    expect(phone.paused, isTrue);
    await mac.stop();
    await a.stop();
    await b.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
