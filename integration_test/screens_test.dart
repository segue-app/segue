// Renders the real app, walks through the main flows and saves screenshots.
// Run via flutter drive (see test_driver/). Network required.
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:integration_test/integration_test.dart';
import 'package:segue/core/library/library.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/catalog/deezer.dart';
import 'package:segue/core/catalog/wave.dart';
import 'package:segue/core/integrations/lastfm.dart';
import 'package:segue/core/downloads/download_manager.dart';
import 'package:segue/core/downloads/downloads.dart';
import 'package:segue/core/import/import.dart';
import 'package:segue/core/local/local_library.dart';
import 'package:segue/core/import/playlist_importer.dart';
import 'package:segue/core/sources/match_source.dart';
import 'package:segue/core/sources/music_source.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/sources.dart';
import 'package:segue/core/sources/youtube_source.dart';
import 'package:segue/core/sync/sync.dart';
import 'package:segue/core/sync/sync_service.dart';
import 'package:segue/main.dart';
import 'package:segue/ui/widgets/motion.dart';
import 'package:segue/ui/widgets/track_actions.dart';
import 'package:segue/ui/widgets/track_tile.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // pump() normally waits for the engine's next frame, which never comes
  // while macOS keeps the test window in the background: the run hangs.
  // benchmarkLive renders whatever frames the engine asks for and turns
  // pump() into a plain wait.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  final shots = <String, String>{};
  final boundary = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    // ignore: avoid_print
    print('STEP shot $name');
    await tester.pump(const Duration(milliseconds: 100));
    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    shots[name] = base64Encode(bytes!.buffer.asUint8List());
  }

  // Waits in real time (network, audio, tickers) while rendering frames.
  Future<void> settle(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('screens', (tester) async {
    // ignore: avoid_print
    print('STEP start');
    MediaKit.ensureInitialized();
    final soundcloud = SoundCloudSource();
    final youtube = YouTubeSource();
    final match = MatchSource(youtube);
    final Map<SourceKind, MusicSource> sources = {
      SourceKind.soundcloud: soundcloud,
      SourceKind.youtube: youtube,
      SourceKind.match: match,
    };
    // ignore: avoid_print
    print('STEP sources');
    final handler = SegueAudioHandler(sources);
    await handler.setVolume(0); // silent: tests must not play out loud
    // ignore: avoid_print
    print('STEP handler');
    // Desktop layout first, whatever size the test window opened at.
    tester.view.physicalSize = const Size(2400, 1500);
    tester.view.devicePixelRatio = 1.5;
    final library = LibraryStore.memory();
    library.setMeta('appearance', '{"lyricsTranslate":true}');
    handler.onTrackStarted = library.recordPlay;
    match.onMatched = (imported, found) {
      if (found.artworkUrl != null) {
        library.fillArtwork(imported, found.artworkUrl!);
      }
    };

    final downloads = DownloadManager(
      library: library,
      sources: sources,
      directory: Directory.systemTemp.createTempSync('segue_dl'),
    );
    handler.localPathFor = library.downloadedPath;
    final localLibrary = LocalLibrary(
      library,
      coversDir: Directory.systemTemp.createTempSync('segue_cov'),
    );
    final sync = SyncService(
      library: library,
      player: handler,
      enableDiscovery: false,
    );
    await sync.start();
    // A second "device" in the same process, standing in for a phone.
    final phoneLibrary = LibraryStore.memory();
    final phone = SyncService(
      library: phoneLibrary,
      player: SegueAudioHandler(sources)..setVolume(0),
      enableDiscovery: false,
    )..deviceName = 'iPhone';
    await phone.start();
    phone.deviceName = 'iPhone';
    phone.platform = 'ios';
    phoneLibrary.setLiked(
      const Track(
        id: 'kJQP7kiw5Fk',
        source: SourceKind.youtube,
        title: 'Despacito',
        artist: 'Luis Fonsi',
        artworkUrl: 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hq720.jpg',
      ),
      true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourcesProvider.overrideWithValue(sources),
          playerProvider.overrideWithValue(handler),
          libraryProvider.overrideWithValue(library),
          syncProvider.overrideWithValue(sync),
          downloadsProvider.overrideWithValue(downloads),
          waveProvider.overrideWithValue(Wave(Catalog(), library, handler)),
          lastFmProvider.overrideWithValue(LastFm(library)),
          localLibraryProvider.overrideWithValue(localLibrary),
          importerProvider.overrideWithValue(
            PlaylistImporter()..soundcloudClientId = soundcloud.clientId,
          ),
        ],
        child: RepaintBoundary(key: boundary, child: const SegueApp()),
      ),
    );
    // ignore: avoid_print
    print('STEP pumped');
    await settle(tester, 2);
    await shot(tester, '01_home_empty');

    // Search tab.
    await tester.tap(find.text('Поиск').first);
    await settle(tester, 1);
    await tester.enterText(find.byType(TextField), 'dua lipa');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 6);

    // Like two results, play the second.
    await tester.tap(find.byType(LikeButton).at(0));
    await tester.tap(find.byType(LikeButton).at(1));
    await tester.tap(find.byType(TrackTile).at(1));
    await settle(tester, 6);
    await shot(tester, '02_search_playing');

    // A playlist with a few results.
    final results = handler.tracks;
    final pid = library.createPlaylist('Вечер');
    library.addToPlaylist(pid, results.take(6).toList());

    await tester.tap(find.text('Главная').first);
    await settle(tester, 2);
    await shot(tester, '03_home_filled');

    await tester.tap(find.text('Библиотека').first);
    await settle(tester, 2);
    await shot(tester, '04_library_liked');

    // Download two tracks and look at the offline section.
    downloads.download(results.take(2).toList());
    await downloads.idle.timeout(const Duration(minutes: 2));
    await tester.tap(find.text('Скачанные').first);
    await settle(tester, 2);
    await shot(tester, '04b_downloaded');
    expect(library.downloadedTracks(), hasLength(2));

    await tester.tap(find.text('Вечер').first);
    await settle(tester, 2);
    await shot(tester, '05_playlist');

    // Track menu.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await settle(tester, 1);
    await shot(tester, '06_track_menu');
    await tester.tapAt(const Offset(5, 5));
    await settle(tester, 1);

    // Import a Yandex Music playlist and play an imported (matched) track.
    await tester.tap(find.text('Импорт по ссылке').first);
    await settle(tester, 1);
    await tester.enterText(
      find.byType(TextField).last,
      'https://music.yandex.ru/users/yamusic-top/playlists/1076',
    );
    await settle(tester, 0.5);
    await shot(tester, '06b_import_dialog');
    await tester.tap(find.text('Импортировать'));
    await settle(tester, 6);
    await shot(tester, '06c_imported_playlist');
    await tester.tap(find.byType(TrackTile).first);
    await settle(tester, 10);
    await shot(tester, '06d_imported_playing');

    // Devices: show a code, pair the "phone", sync.
    await tester.tap(find.text('Устройства').first);
    await settle(tester, 1);
    await tester.tap(find.text('Показать код'));
    await settle(tester, 1);
    await shot(tester, '06e_devices_code');
    final dev = await phone.probe('127.0.0.1', sync.port);
    await phone.pair(dev, sync.pairingCode.value!);
    await sync.probe('127.0.0.1', phone.port); // "seen on the network"
    await phone.syncWith(phoneLibrary.peers().single.id);
    await settle(tester, 2);
    await shot(tester, '06f_devices_paired');
    expect(library.likedKeys(), contains('youtube:kJQP7kiw5Fk'));

    await tester.tap(find.text('Настройки').first);
    await settle(tester, 2);
    await shot(tester, '06g_settings');
    // Tapping the same menu item again must not stack another page.
    await tester.tap(find.text('Настройки').first);
    await settle(tester, 1);
    expect(find.text('Сбросить'), findsOneWidget);

    // Home must show Home even after visiting other sections.
    await tester.tap(find.text('Главная').first);
    await settle(tester, 1);
    expect(find.textContaining('Добр'), findsWidgets);

    // Desktop player with lyrics: cover left, lyrics right.
    unawaited(handler.playList(results, 1)); // a track that has lyrics
    await settle(tester, 6);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.lyrics_rounded));
    await settle(tester, 0.3);
    await shot(tester, '06h0_lyrics_opening');
    await settle(tester, 4);
    await shot(tester, '06h_desktop_lyrics');
    await tester.tap(find.byIcon(Icons.equalizer_rounded).last);
    await settle(tester, 1);
    await tester.tap(find.text('Бас'));
    await settle(tester, 1);
    await shot(tester, '06i_sound_sheet');
    await tester.tapAt(const Offset(5, 300));
    await settle(tester, 1);
    await tester.tap(find.byIcon(Icons.lyrics_rounded));
    await settle(tester, 0.3);
    await shot(tester, '06h1_lyrics_closing');
    await settle(tester, 1.5);
    await shot(tester, '06h2_lyrics_closed');
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await settle(tester, 1);

    // Catalogue: artist from search, their page, an album, their wave.
    await tester.tap(find.text('Поиск').first);
    await settle(tester, 1);
    await tester.enterText(find.byType(TextField), 'miyagi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 6);
    await shot(tester, '07a_search_artists');
    await tester.tap(find.text('Артист').first);
    await settle(tester, 4);
    await shot(tester, '07b_artist');
    await tester.tap(find.text('Волна артиста'));
    await settle(tester, 6);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.queue_music_rounded).last);
    await settle(tester, 2);
    await shot(tester, '07c_wave_queue');
    expect(handler.waveTitle.value, startsWith('Волна'));
    await tester.tapAt(const Offset(5, 5));
    await settle(tester, 1);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await settle(tester, 1);
    await tester.tap(find.text('Главная').first);
    await settle(tester, 3);
    await shot(tester, '07d_home_wave_charts');
    await tester.tap(find.text('Настроить'));
    await settle(tester, 1);
    await tester.tap(find.text('Грустное'));
    await tester.tap(find.text('Русский'));
    await settle(tester, 1);
    await shot(tester, '07e_wave_settings');
    await tester.tap(find.text('Слушать'));
    await settle(tester, 10);
    await shot(tester, '07f_my_wave_playing');
    expect(handler.waveTitle.value, 'Моя волна');

    // Phone layout.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await settle(tester, 2);
    await shot(tester, '07_phone_playlist');
    await tester.tap(find.text('Главная').first);
    await settle(tester, 2);
    await shot(tester, '08_phone_home');
    await tester.tap(find.byType(PressScale).last); // mini player area
    await tester.tap(find.byType(Hero).first, warnIfMissed: false);
    await settle(tester, 3);
    await shot(tester, '09_phone_now_playing');

    await tester.tap(find.byIcon(Icons.lyrics_rounded));
    await settle(tester, 5);
    await shot(tester, '10_phone_lyrics');
    await settle(tester, 0.7);
    await shot(tester, '10b_phone_lyrics');

    expect(tester.takeException(), isNull);
    await handler.stop();
    binding.reportData = shots;
  }, timeout: const Timeout(Duration(minutes: 5)));
}
