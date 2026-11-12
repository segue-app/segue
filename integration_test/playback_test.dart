import 'dart:math';
// Plays real tracks through the real player (libmpv) — muted — and checks
// that playback, seeking and the audio effects chain all work. Network needed.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/downloads/audio_cache.dart';
import 'package:segue/core/downloads/download_manager.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/audio_fx.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/match_source.dart';
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';
import 'package:segue/core/sources/sponsorblock.dart';
import 'package:segue/core/catalog/deezer.dart';

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

  testWidgets('a quick skip: old song stops, new one starts at 0', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    final tracks = await yt.search('zivert life', limit: 3);
    await player.playList(tracks, 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 40));
    // Deep into the first song, then skip twice in a row.
    await player.seek(const Duration(seconds: 90));
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 90))
        .timeout(const Duration(seconds: 20));
    final seen = <Duration>[];
    final sub = player.positionStream.listen(seen.add);
    unawaited(player.skipToNext());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    // The old song must already be silent: no more of its positions.
    // Stopped (nothing loaded) or already the next song near its start.
    final at = double.tryParse(await player.debugProperty('time-pos')) ?? 0;
    // Seeking while the next one loads must not carry over.
    await player.seek(const Duration(seconds: 120));
    await player.skipToNext();
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 2))
        .timeout(const Duration(seconds: 40));
    await Future<void>.delayed(const Duration(seconds: 1));
    await sub.cancel();
    final pos = player.position;
    // ignore: avoid_print
    print(
      'QUICK SKIP: mpv at ${at}s 150ms after skip, now ${player.current?.title} '
      'at ${pos.inMilliseconds}ms; positions after skip: '
      '${seen.map((d) => d.inSeconds).toSet()}',
    );
    expect(player.index, 2);
    expect(at, lessThan(10));
    expect(pos, lessThan(const Duration(seconds: 15)));
    // Nothing from the old song's 90 s+ leaked after the skip.
    expect(seen.where((d) => d > const Duration(seconds: 30)), isEmpty);
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('gapless: the next song follows with no reload', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0);
    final tracks = await yt.search('miyagi andy panda', limit: 3);
    await player.playList(tracks.take(2).toList(), 0);
    final dur = await player.durationStream
        .firstWhere((d) => d != null && d > Duration.zero)
        .timeout(const Duration(seconds: 40));
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 40));
    // Near the end: the next one gets queued in mpv, then takes over.
    await player.seek(dur! - const Duration(seconds: 12));
    final sw = Stopwatch()..start();
    await player.mediaItem
        .firstWhere((m) => m?.id == tracks[1].key)
        .timeout(const Duration(seconds: 40));
    final switchedAfter = sw.elapsed;
    final firstPos = await player.positionStream
        .firstWhere((p) => p > Duration.zero)
        .timeout(const Duration(seconds: 10));
    final playlist = await player.debugProperty('playlist-count');
    // ignore: avoid_print
    print(
      'GAPLESS switched ${switchedAfter.inSeconds}s after seeking 12 s '
      'before the end; new song at ${firstPos.inMilliseconds} ms; '
      'mpv playlist $playlist; index ${player.index}',
    );
    expect(player.index, 1);
    expect(firstPos, lessThan(const Duration(seconds: 3)));
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await player.debugProperty('playlist-count'), '1');
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('loudness: loud songs are turned down', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    double? seen;
    player.saveLoudness = (_, db) => seen = db;
    await player.setVolume(0.5);
    final t = (await yt.search('the weeknd blinding lights audio', limit: 1))
        .first;
    // Silent anyway: the test checks the volume mpv is given.
    await player.debugSetProperty('mute', 'yes');
    await player.playList([t], 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 40));
    final on = double.parse(await player.debugProperty('volume'));
    await player.setNormalize(false);
    final off = double.parse(await player.debugProperty('volume'));
    // ignore: avoid_print
    print('LOUDNESS ${seen}dB → volume $on with, $off without');
    expect(seen, isNotNull);
    expect(off, closeTo(50, 0.5));
    // 7 dB above YouTube's reference is a typical modern song: about
    // the same volume (it used to come out at less than half).
    expect(on, closeTo(off * pow(10, (6 - seen!) / 20), 1));
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('offline cache keeps a song and plays it from disk', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final sources = <SourceKind, MusicSource>{SourceKind.youtube: yt};
    final library = LibraryStore.memory();
    final tmp = Directory.systemTemp.createTempSync('cache_test');
    final cache = AudioCache(
      library: library,
      downloads: DownloadManager(
        library: library,
        sources: sources,
        directory: Directory('${tmp.path}/dl')..createSync(),
      ),
      sources: sources,
      directory: Directory('${tmp.path}/cache')..createSync(),
    );
    final t = (await yt.search('zivert life audio', limit: 1)).first;
    final sw = Stopwatch()..start();
    await cache.keep(t);
    final path = cache.pathFor(t);
    // ignore: avoid_print
    print(
      'CACHE kept in ${sw.elapsedMilliseconds} ms: $path '
      '(${cache.bytes.value ~/ 1024} KB)',
    );
    expect(path, isNotNull);
    expect(File(path!).lengthSync(), greaterThan(500000));
    // The player takes the file instead of the network.
    final player = SegueAudioHandler(sources)..localPathFor = cache.pathFor;
    await player.setVolume(0);
    final start = Stopwatch()..start();
    await player.playList([t], 0);
    await player.positionStream
        .firstWhere((p) => p > const Duration(milliseconds: 300))
        .timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('CACHE started from disk in ${start.elapsedMilliseconds} ms');
    expect(await player.debugProperty('path'), contains(tmp.path));
    await player.stop();
    await cache.clear();
    expect(cache.pathFor(t), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('handoff plays the exact version the other device played', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final match = MatchSource(yt);
    final player = SegueAudioHandler({
      SourceKind.youtube: yt,
      SourceKind.match: match,
    });
    player
      ..matchOf = match.matched
      ..adoptMatch = match.choose;
    await player.setVolume(0);
    const imported = Track(
      id: 'imp-zivert-life',
      source: SourceKind.match,
      title: 'Life',
      artist: 'Zivert',
      duration: Duration(seconds: 188),
    );
    // Not what a search here would pick: the other device's own choice.
    final found = await match.candidates(imported);
    final theirs = found[2].track;
    await player.restore({
      'queue': [imported.toJson()],
      'index': 0,
      'positionMs': 30000,
      'playing': true,
      'matches': {imported.key: theirs.toJson()},
    });
    await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 31))
        .timeout(const Duration(seconds: 40));
    final mine = match.matched(imported);
    final sent = (player.snapshot()['matches'] as Map)[imported.key] as Map;
    // ignore: avoid_print
    print(
      'HANDOFF theirs ${theirs.id} "${theirs.title}", plays ${mine?.id}, '
      'search would pick ${found.first.track.id}; passes on ${sent['id']}',
    );
    expect(mine?.id, theirs.id);
    expect(sent['id'], theirs.id);
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));

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

  testWidgets('DJ mix: skips the intro, crossfades, matches tempo', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    final sb = SponsorBlock();
    final catalog = Catalog();
    player
      ..fadeSeconds = 6
      ..autoBounds = ((t) => sb.musicBounds(t.id))
      ..bpmFor = ((t) => catalog.bpm(t.artist, t.title));
    final a = (await yt.search(
      'Luis Fonsi Despacito ft. Daddy Yankee',
      limit: 3,
    )).firstWhere((t) => t.id == 'kJQP7kiw5Fk');
    final b = (await yt.search(
      'Ed Sheeran Shape of You official',
      limit: 1,
    )).first;
    await player.playList([
      a.copyWithArtist('Luis Fonsi', 'Despacito'),
      b.copyWithArtist('Ed Sheeran', 'Shape of You'),
    ], 0);
    final first = await player.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 40));
    // SponsorBlock: the spoken intro (0:00–0:21) is skipped.
    expect(first, greaterThan(const Duration(seconds: 20)));
    // Near the end of the music (4:09 per SponsorBlock), the mix begins.
    await player.seek(const Duration(seconds: 236));
    final sw = Stopwatch()..start();
    while (player.index == 0 && sw.elapsed < const Duration(seconds: 30)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final switchedAt = sw.elapsedMilliseconds;
    final speed = double.parse(await player.debugProperty('speed'));
    await Future<void>.delayed(const Duration(seconds: 8));
    final later = double.parse(await player.debugProperty('speed'));
    // ignore: avoid_print
    print(
      'MIX switched after ${switchedAt}ms (music ends ~13s after the seek), '
      'speed at start $speed, 8s later $later',
    );
    expect(player.index, 1);
    expect(switchedAt, lessThan(11000)); // before the old song's music ended
    expect(speed, lessThan(0.999)); // brought to Despacito's slower tempo
    expect(later, greaterThan(speed)); // easing back to its own
    await player.stop();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

extension on Track {
  Track copyWithArtist(String artist, String title) => Track(
    id: id,
    source: source,
    title: title,
    artist: artist,
    artworkUrl: artworkUrl,
    duration: duration,
  );
}
