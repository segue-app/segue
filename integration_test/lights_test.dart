// Lights follow a real (muted) song: a fake WLED strip records the frames
// and the flashes come at the song's tempo.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/dj/beat_service.dart';
import 'package:segue/core/lights/light_devices.dart';
import 'package:segue/core/lights/light_sync.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lights flash on the beats of a real song', (tester) async {
    MediaKit.ensureInitialized();
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((r) => r.response
      ..write(jsonEncode({'leds': {'count': 30}}))
      ..close());
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final frames = <(int, int)>[]; // ms, red level
    final clock = Stopwatch()..start();
    udp.listen((_) {
      final d = udp.receive();
      if (d != null) frames.add((clock.elapsedMilliseconds, d.data[4]));
    });

    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    player.beats = BeatService(uriFor: player.analysisUri);
    final lights = LightSync(player: player)
      ..palette = const [(r: 255, g: 0, b: 0)]
      ..latencyMs = 0;
    await lights.add(
      WledDevice('127.0.0.1', httpPort: http.port, udpPort: udp.port),
    );
    await lights.setEnabled(true);
    final song = (await yt.search('Daft Punk Get Lucky official audio', limit: 1)).first;
    await player.playList([song], 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 40));
    await player.seek(const Duration(seconds: 70));
    // The beat is analysed, then 10 s of flashes.
    await Future<void>.delayed(const Duration(seconds: 8));
    final from = clock.elapsedMilliseconds;
    await Future<void>.delayed(const Duration(seconds: 10));
    final heard = frames.where((f) => f.$1 >= from).toList();
    // Flashes: from the dim end of a beat up to a bright start (the
    // first beat of a bar is brightest, the others less).
    final flashes = <int>[];
    final bars = <int>[];
    for (var i = 1; i < heard.length; i++) {
      if (heard[i].$2 > 140 && heard[i - 1].$2 < 80) flashes.add(heard[i].$1);
      if (heard[i].$2 > 200 && heard[i - 1].$2 < 150) bars.add(heard[i].$1);
    }
    final gaps = [
      for (var i = 1; i < flashes.length; i++) flashes[i] - flashes[i - 1],
    ]..sort();
    final median = gaps.isEmpty ? 0 : gaps[gaps.length ~/ 2];
    // ignore: avoid_print
    print('LIGHTS ${heard.length} frames in 10 s, ${flashes.length} flashes, '
        'median gap $median ms (116 bpm = 517 ms)');
    expect(heard.length, greaterThan(200)); // ~30 a second
    expect(median, closeTo(517, 40));
    // Every fourth one is the bar's first, brighter.
    final barGap = bars.length < 2 ? 0 : (bars.last - bars.first) / (bars.length - 1);
    expect(barGap, closeTo(4 * 517, 80));
    await lights.setEnabled(false);
    await player.stop();
    udp.close();
    await http.close(force: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
