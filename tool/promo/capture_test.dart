// ignore_for_file: invalid_use_of_visible_for_testing_member
// Records a phone-sized video of one song with its lyrics, frame by frame
// from inside the app (a COPY of the real library; nothing synced, sound
// off). Frames + their song positions go to the app's temp folder; then
// tool/promo/make.sh turns them into an Instagram video with the audio.
// Run: flutter drive -d macos --driver test_driver/integration_test.dart
//        --target tool/promo/capture_test.dart
//        --dart-define=PROMO_ID=<youtube id> --dart-define=PROMO_END_MS=…
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path_provider/path_provider.dart';
import 'package:segue/core/catalog/deezer.dart';
import 'package:segue/core/catalog/taste.dart';
import 'package:segue/core/catalog/wave.dart';
import 'package:segue/core/downloads/audio_cache.dart';
import 'package:segue/core/downloads/download_manager.dart';
import 'package:segue/core/downloads/downloads.dart';
import 'package:segue/core/import/import.dart';
import 'package:segue/core/import/playlist_importer.dart';
import 'package:segue/core/integrations/lastfm.dart';
import 'package:segue/core/library/library.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/local/local_library.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/settings/settings.dart';
import 'package:segue/core/sources/match_source.dart';
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/sources.dart';
import 'package:segue/core/sources/youtube_source.dart';
import 'package:segue/core/sync/connect.dart';
import 'package:segue/core/sync/jam.dart';
import 'package:segue/core/sync/relay.dart';
import 'package:segue/core/sync/sync.dart';
import 'package:segue/core/sync/sync_service.dart';
import 'package:segue/ui/screens/now_playing_screen.dart';
import 'package:segue/core/app_visibility.dart';
import 'package:segue/main.dart';
import 'package:segue/ui/widgets/motion.dart';
import 'package:segue/core/sync/shared_playlists.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  final boundary = GlobalKey();

  Future<void> settle(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('promo capture', (tester) async {
    final clock = StreamController<Duration>.broadcast();
    MediaKit.ensureInitialized();
    // A copy of the real library.
    final real = '${(await getApplicationSupportDirectory()).path}/library.db';
    final tmp = Directory.systemTemp.createTempSync('segue_shots');
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$real$ext');
      if (f.existsSync()) f.copySync('${tmp.path}/library.db$ext');
    }
    final library = LibraryStore.at('${tmp.path}/library.db');

    final soundcloud = SoundCloudSource();
    final youtube = YouTubeSource();
    final match = MatchSource(youtube);
    match.recall = (key) {
      final j = library.kvGet('match', key);
      return j is Map ? Track.fromJson(j.cast<String, dynamic>()) : null;
    };
    final Map<SourceKind, MusicSource> sources = {
      SourceKind.soundcloud: soundcloud,
      SourceKind.youtube: youtube,
      SourceKind.match: match,
    };
    final handler = SegueAudioHandler(sources);
    await handler.setVolume(0); // silent
    final downloads = DownloadManager(
      library: library,
      sources: sources,
      directory: Directory('${tmp.path}/dl')..createSync(),
    );
    // Not started: nothing leaves this process.
    final sync = SyncService(
      library: library,
      player: handler,
      enableDiscovery: false,
    );
    final relay = Relay(
      library: library,
      player: handler,
      deviceName: () => 'Mac',
    );
    final catalog = Catalog();
    final taste = Taste(library);

    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourcesProvider.overrideWithValue(sources),
          playerProvider.overrideWithValue(handler),
          libraryProvider.overrideWithValue(library),
          syncProvider.overrideWithValue(sync),
          connectProvider.overrideWithValue(
            Connect(
              sync: sync,
              relay: relay,
              library: library,
              player: handler,
            ),
          ),
          jamProvider.overrideWithValue(
            JamService(
              player: handler,
              deviceId: library.deviceId,
              name: () => 'Mac',
            ),
          ),
          downloadsProvider.overrideWithValue(downloads),
          sharedPlaylistsProvider.overrideWithValue(
            SharedPlaylists(library: library, deviceName: () => 'Mac'),
          ),
          audioCacheProvider.overrideWithValue(
            AudioCache(
              library: library,
              downloads: downloads,
              sources: sources,
              directory: Directory('${tmp.path}/cache')..createSync(),
            )..enabled = false,
          ),
          tasteProvider.overrideWithValue(taste),
          waveProvider.overrideWithValue(
            Wave(catalog, library, handler, taste: taste),
          ),
          lastFmProvider.overrideWithValue(LastFm(library)),
          localLibraryProvider.overrideWithValue(
            LocalLibrary(
              library,
              coversDir: Directory('${tmp.path}/cov')..createSync(),
            ),
          ),
          importerProvider.overrideWithValue(PlaylistImporter()),
          // The picture follows a clock of our own: one frame of video at a
          // time, however long drawing it takes.
          positionProvider.overrideWith((ref) => clock.stream),
          playingProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: RepaintBoundary(key: boundary, child: const SegueApp()),
      ),
    );
    await settle(tester, 3);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SegueApp)),
    );

    const id = String.fromEnvironment('PROMO_ID');
    const fromMs = int.fromEnvironment('PROMO_FROM_MS', defaultValue: 5000);
    const endMs = int.fromEnvironment('PROMO_END_MS', defaultValue: 15000);
    final track = Track(
      id: id,
      source: SourceKind.youtube,
      title: const String.fromEnvironment('PROMO_TITLE'),
      artist: const String.fromEnvironment('PROMO_ARTIST'),
      artworkUrl: 'https://i.ytimg.com/vi/$id/hq720.jpg',
      duration: const Duration(
        milliseconds: int.fromEnvironment('PROMO_LENGTH_MS'),
      ),
    );
    container
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(language: 'ru', playerStyle: PlayerStyle.classic),
        );
    NowPlayingScreen.debugDesktop = false; // the phone's controls
    // Keeps animating if this window goes behind another one meanwhile.
    AppVisibility.debugAlwaysActive = true;
    AppVisibility.visibleNotifier.value = true;
    // A phone screen, 9:16, drawn at 1080 × 1920.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.7;
    await settle(tester, 2);

    // Loaded (title, cover, length) but silent and still: the picture
    // runs on the clock below, not on playback.
    await handler.playList([track], 0);
    await handler.debugSetProperty('mute', 'yes');
    await handler.positionStream
        .firstWhere((p) => p > Duration.zero)
        .timeout(const Duration(seconds: 60));
    await handler.pause();
    clock.add(Duration(milliseconds: fromMs - 3000));
    await tester.tap(find.byType(PressScale).last); // the mini player
    await tester.tap(find.byType(Hero).first, warnIfMissed: false);
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 4);

    // Every animation runs [slow] times slower and each frame takes
    // [slow] × 1/30 s to draw: in the video it all moves at true speed.
    const slow = 6.0;
    const frameMs = 1000 / 30;
    timeDilation = slow;
    final settings = container.read(settingsProvider);
    container
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(backdropSpeed: settings.backdropSpeed / slow),
        );
    // A lead-in so lines and colours are where they'd be.
    for (var t = fromMs - 3000.0; t < fromMs; t += frameMs) {
      clock.add(Duration(milliseconds: t.round()));
      await tester.pump();
      await Future<void>.delayed(
        Duration(milliseconds: (frameMs * slow).round()),
      );
    }

    final out = Directory('${Directory.systemTemp.path}/segue_promo');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final writes = <Future<void>>[];
    final sw = Stopwatch()..start();
    var n = 0, late = 0;
    for (var t = fromMs.toDouble(); t < endMs; t += frameMs) {
      final started = sw.elapsedMilliseconds;
      clock.add(Duration(milliseconds: t.round()));
      await tester.pump();
      final image = await ro.toImage(pixelRatio: 2.7);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      writes.add(
        File('${out.path}/f${n.toString().padLeft(5, '0')}.png')
            .writeAsBytes(bytes!.buffer.asUint8List()),
      );
      n++;
      final left =
          (frameMs * slow).round() - (sw.elapsedMilliseconds - started);
      if (left > 0) {
        await Future<void>.delayed(Duration(milliseconds: left));
      } else {
        late++;
      }
    }
    await Future.wait(writes);
    timeDilation = 1;
    // The song itself, the same recording, for the soundtrack.
    final audio = await downloads.fetchTo(track, out);
    // ignore: avoid_print
    print('PROMO $n frames (late $late) -> ${out.path}, audio ${audio.path}');
    await handler.stop();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
