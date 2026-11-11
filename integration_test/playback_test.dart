// Plays real tracks through the real player (libmpv) — muted — and checks
// that playback, seeking and the audio effects chain all work. Network needed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/downloads/download_manager.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/audio_fx.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tracks play, seek and take effects', (tester) async {
    MediaKit.ensureInitialized();
    final sources = <SourceKind, MusicSource>{
      SourceKind.youtube: YouTubeSource(),
      SourceKind.soundcloud: SoundCloudSource(),
    };
    final player = SegueAudioHandler(sources);
    final library = LibraryStore.memory();
    player.seekableCopy = DownloadManager(
      library: library,
      sources: sources,
      directory: Directory.systemTemp.createTempSync('pb_dl'),
    ).seekableCopy;
    await player.setVolume(0); // silent

    Future<Duration> waitPast(Duration target) => player.positionStream
        .firstWhere((p) => p > target)
        .timeout(const Duration(seconds: 40));

    const only = String.fromEnvironment('ONLY');
    for (final s in sources.values) {
      if (only.isNotEmpty && s.kind.name != only) continue;
      final t = (await s.search('miyagi фея', limit: 2)).first;
      await player.playList([t], 0);
      final started = await waitPast(const Duration(seconds: 2));

      final dur = await player.durationStream
          .firstWhere((d) => d != null && d > Duration.zero)
          .timeout(const Duration(seconds: 20));
      await player.seek(dur! * 0.6);
      final afterSeek = await waitPast(dur * 0.6 + const Duration(seconds: 1));

      final fx = AudioFx(
        eqOn: true,
        gains: AudioFx.presets['Бас']!,
        speed: 1.25,
        semitones: 2,
      );
      await player.applyFx(fx);
      final before = afterSeek;
      final withFx = await waitPast(before + const Duration(seconds: 2));
      final af = await player.debugProperty('af');
      final speed = await player.debugProperty('speed');
      // ignore: avoid_print
      print(
        'PLAYBACK ${s.label}: "${t.title}" started ${started.inSeconds}s, '
        'seek→${afterSeek.inSeconds}s of ${dur.inSeconds}s, fx→${withFx.inSeconds}s; '
        'speed=$speed af=${af.length > 90 ? '${af.substring(0, 90)}…' : af}',
      );
      expect(af, contains('equalizer'));
      expect(double.parse(speed), closeTo(fx.mpvSpeed, 0.001));
      await player.applyFx(const AudioFx());
    }
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('switching tracks is fast', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    final tracks = await yt.search('miyagi andy panda', limit: 4);
    final sw = Stopwatch()..start();
    Future<int> started() async {
      sw.reset();
      // Position resets on open; wait for real progress of the new track.
      var reset = false;
      await player.positionStream
          .firstWhere((p) {
            if (p < const Duration(milliseconds: 300)) reset = true;
            return reset && p > const Duration(milliseconds: 300);
          })
          .timeout(const Duration(seconds: 40));
      return sw.elapsedMilliseconds;
    }

    final times = <int>[];
    final first = started();
    await player.playList(tracks, 0);
    times.add(await first);
    for (var i = 1; i < tracks.length; i++) {
      // Listen for a few seconds, like a person would before skipping.
      await Future<void>.delayed(const Duration(seconds: 4));
      final next = started();
      await player.skipToNext();
      times.add(await next);
    }
    // ignore: avoid_print
    print('SWITCH ms: $times');
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('trimmed track starts and ends at its trim', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    final tracks = await yt.search('miyagi kosandra', limit: 2);
    player.trimFor = (t) => t.key == tracks[0].key
        ? (start: const Duration(seconds: 30), end: const Duration(seconds: 36))
        : null;
    await player.playList(tracks, 0);
    final first = await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 30));
    expect(first, greaterThan(const Duration(seconds: 29)));
    // Moves on to the next track at 0:36.
    final sw = Stopwatch()..start();
    while (player.index == 0 && sw.elapsed < const Duration(seconds: 25)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // ignore: avoid_print
    print(
      'TRIM started at ${first.inSeconds}s, moved on after ${sw.elapsed.inSeconds}s',
    );
    expect(player.index, 1);
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
