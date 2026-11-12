// Screenshots for the README from a COPY of the real library on this
// computer (the original isn't touched, nothing is synced, sound is off).
// Run: flutter drive -d macos --driver test_driver/integration_test.dart
//        --target integration_test/readme_shots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:segue/main.dart';
import 'package:segue/ui/widgets/motion.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  final shots = <String, String>{};
  final boundary = GlobalKey();

  Future<void> shot(WidgetTester tester, String name, double ratio) async {
    await tester.pump(const Duration(milliseconds: 100));
    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    shots[name] = base64Encode(bytes!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('readme screenshots', (tester) async {
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
    final matches =
        jsonDecode(library.getMeta('matches2') ?? '{}') as Map<String, dynamic>;
    match.recall = (key) {
      final j = matches[key];
      return j == null
          ? null
          : Track.fromJson((j as Map).cast<String, dynamic>());
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
            Connect(sync: sync, relay: relay, library: library, player: handler),
          ),
          jamProvider.overrideWithValue(
            JamService(
              player: handler,
              deviceId: library.deviceId,
              name: () => 'Mac',
            ),
          ),
          downloadsProvider.overrideWithValue(downloads),
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
        ],
        child: RepaintBoundary(key: boundary, child: const SegueApp()),
      ),
    );
    await settle(tester, 3);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SegueApp)),
    );
    Future<void> language(String code) async {
      container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(language: code));
      await settle(tester, 2);
    }

    // Something from the likes, a few seconds in.
    final liked = library.likedTracks();
    await handler.playList(liked.take(30).toList(), 0);
    await handler.positionStream
        .firstWhere((p) => p > const Duration(seconds: 1))
        .timeout(const Duration(seconds: 60));
    await handler.seek(const Duration(seconds: 40));
    await settle(tester, 6);

    Future<void> desktop(String lang) async {
      tester.view.physicalSize = const Size(2880, 1800);
      tester.view.devicePixelRatio = 2;
      await language(lang);
      await settle(tester, 3);
      await shot(tester, '$lang/home', 1.1);
      await tester.tap(find.byIcon(Icons.open_in_full_rounded));
      await settle(tester, 3);
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await settle(tester, 6);
      await shot(tester, '$lang/lyrics', 1.1);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await settle(tester, 2);
    }

    Future<void> phone(String lang) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      await language(lang);
      await settle(tester, 3);
      await shot(tester, '$lang/phone-home', 1.5);
      await tester.tap(find.byType(PressScale).last);
      await tester.tap(find.byType(Hero).first, warnIfMissed: false);
      await settle(tester, 4);
      await shot(tester, '$lang/phone-player', 1.5);
      await tester.tap(find.byIcon(Icons.lyrics_rounded));
      await settle(tester, 6);
      await shot(tester, '$lang/phone-lyrics', 1.5);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await settle(tester, 2);
    }

    await desktop('en');
    await desktop('ru');
    await phone('ru');
    await phone('en');

    await handler.stop();
    binding.reportData = shots;
  }, timeout: const Timeout(Duration(minutes: 8)));
}
