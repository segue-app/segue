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
import 'package:segue/core/sync/connect.dart';
import 'package:segue/core/sync/jam.dart';
import 'package:segue/core/sync/relay.dart';
import 'package:segue/core/sync/sync.dart';
import 'package:segue/core/sync/sync_service.dart';
import 'package:segue/main.dart';
import 'package:segue/ui/widgets/motion.dart';
import 'package:segue/ui/screens/mix_screen.dart';
import 'package:segue/ui/screens/artist_screen.dart';
import 'package:segue/core/settings/settings.dart';
import 'package:segue/ui/screens/now_playing_screen.dart';
import 'package:segue/ui/screens/cover_player.dart';
import 'package:segue/ui/widgets/volume_slider.dart';
import 'package:segue/ui/widgets/h_scroll.dart';
import 'package:segue/ui/widgets/wavy_progress.dart';
import 'package:segue/ui/widgets/mini_player.dart';
import 'package:segue/core/downloads/audio_cache.dart';
import 'package:segue/ui/screens/settings_screen.dart';
import 'package:segue/ui/screens/album_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:segue/ui/widgets/track_actions.dart';
import 'package:segue/ui/widgets/track_tile.dart';
import 'package:segue/core/sync/shared_playlists.dart';

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

    // Internet relay for both "devices" (the real public brokers).
    final phonePlayer = SegueAudioHandler(sources)..setVolume(0);
    final relay = Relay(
      library: library,
      player: handler,
      deviceName: () => 'MacBook',
    );
    final phoneRelay = Relay(
      library: phoneLibrary,
      player: phonePlayer,
      deviceName: () => 'iPhone',
      platform: 'ios',
    );
    await relay.start();
    await phoneRelay.start();
    final connect = Connect(
      sync: sync,
      relay: relay,
      library: library,
      player: handler,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourcesProvider.overrideWithValue(sources),
          playerProvider.overrideWithValue(handler),
          libraryProvider.overrideWithValue(library),
          syncProvider.overrideWithValue(sync),
          connectProvider.overrideWithValue(connect),
          jamProvider.overrideWithValue(
            JamService(
              player: handler,
              deviceId: library.deviceId,
              name: () => 'MacBook',
            ),
          ),
          downloadsProvider.overrideWithValue(downloads),
          audioCacheProvider.overrideWithValue(
            AudioCache(
              library: library,
              downloads: downloads,
              sources: sources,
              directory: Directory.systemTemp.createTempSync('segue_cache'),
            )..enabled = false,
          ),
          sharedPlaylistsProvider.overrideWithValue(
            SharedPlaylists(library: library, deviceName: () => 'Mac'),
          ),
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
    // Listening history: by day, searchable.
    await tester.tap(find.text('История').first);
    await settle(tester, 2);
    await shot(tester, '04c_history');
    expect(find.text('Сегодня'), findsOneWidget);

    await tester.tap(find.text('Вечер').first);
    await settle(tester, 2);
    await shot(tester, '05_playlist');
    // Search in the list.
    await tester.enterText(find.byType(TextField).last, 'zzzz-none');
    await settle(tester, 0.5);
    expect(find.text('Ничего не нашлось'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '');
    await settle(tester, 0.5);

    // Track menu.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await settle(tester, 1);
    await shot(tester, '06_track_menu');
    await tester.tapAt(const Offset(5, 5));
    await settle(tester, 1);

    // Import a Yandex Music playlist and play an imported (matched) track.
    // Import lives in Settings now.
    await tester.tap(find.text('Настройки').first);
    await settle(tester, 1);
    await tester.tap(find.text('Импорт плейлиста по ссылке'));
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
    await tester.tap(find.byType(TrackTile).first, warnIfMissed: false);
    await settle(tester, 10);
    await shot(tester, '06d_imported_playing');

    // Devices (in Settings): show a code, the "phone" joins over the relay.
    await tester.tap(find.text('Настройки').first);
    await settle(tester, 1);
    await tester.tap(find.text('Устройства').first);
    await settle(tester, 1);
    await tester.tap(find.text('Добавить устройство'));
    await settle(tester, 4);
    expect(find.text('Код для другого устройства'), findsOneWidget);
    await shot(tester, '06e_devices_code');
    await phoneRelay.join(connect.inviteCode.value!);
    // The phone plays (muted); this device stops, so the remote bar shows.
    await handler.pause();
    unawaited(
      phonePlayer.playList([
        const Track(
          id: 'kJQP7kiw5Fk',
          source: SourceKind.youtube,
          title: 'Despacito',
          artist: 'Luis Fonsi',
          artworkUrl: 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hq720.jpg',
          duration: Duration(minutes: 4, seconds: 41),
        ),
      ], 0),
    );
    // Wait for the phone's like and its playback to come over the relay.
    for (var i = 0; i < 60; i++) {
      final phoneNow = relay.devices.value[phoneLibrary.deviceId];
      if (phoneNow?.playing == true &&
          library.likedKeys().contains('youtube:kJQP7kiw5Fk')) {
        break;
      }
      await settle(tester, 1);
    }
    await settle(tester, 2);
    expect(
      library.isLiked(
        const Track(
          id: 'kJQP7kiw5Fk',
          source: SourceKind.youtube,
          title: 'Despacito',
          artist: 'Luis Fonsi',
        ),
      ),
      isTrue,
      reason: 'the phone\'s like came over the relay',
    );
    await shot(tester, '06f_devices_paired');
    expect(library.likedKeys(), contains('youtube:kJQP7kiw5Fk'));
    // Spotify-style: this idle Mac becomes the remote for the phone, in
    // its own player.
    expect(handler.output.value, 'iPhone');
    expect(find.text('Играет на iPhone'), findsWidgets);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await settle(tester, 3);
    await shot(tester, '06f2_remote_player');
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await settle(tester, 1);
    await phonePlayer.pause();
    handler.leaveRemote();

    await tester.tap(find.text('Настройки').first);
    await settle(tester, 2);
    await shot(tester, '06g_settings');
    // Categories: each opens its own settings beside the list.
    await tester.tap(find.text('Звук и воспроизведение'));
    await settle(tester, 1);
    expect(find.text('Высокое качество звука'), findsOneWidget);
    await shot(tester, '06g1_settings_sound');
    await tester.tap(find.text('Внешний вид'));
    await settle(tester, 1);
    await shot(tester, '06g2_settings_look');
    // Tapping the same menu item again must not stack another page.
    await tester.tap(find.text('Настройки').first);
    await settle(tester, 1);
    expect(find.text('Сбросить'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    // Support the author: the bank codes and Boosty, inside the app.
    await tester.tap(find.text('О приложении'));
    await settle(tester, 1);
    await tester.tap(find.text('Поддержать автора'));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('support-boosty')), findsOneWidget);
    expect(find.text('Mbank'), findsOneWidget);
    await shot(tester, '06g3_support');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester, 1);

    // Home must show Home even after visiting other sections.
    await tester.tap(find.text('Главная').first);
    await settle(tester, 1);
    expect(find.textContaining('Добр'), findsWidgets);

    // Desktop player with lyrics: cover left, lyrics right.
    unawaited(handler.playList(results, 1)); // a track that has lyrics
    await settle(tester, 6);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await settle(tester, 2);
    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 0.3);
    await shot(tester, '06h0_lyrics_opening');
    await settle(tester, 4);
    await shot(tester, '06h_desktop_lyrics');
    // Left alone while music plays, the top buttons fade; a move brings
    // them back.
    double topOpacity() => tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.byIcon(Icons.lyrics_rounded).last,
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .map((w) => w.opacity)
        .reduce((a, b) => a < b ? a : b);
    await settle(tester, 4);
    await shot(tester, '06h00_buttons_faded');
    expect(topOpacity(), lessThan(0.5));
    final idleMouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await idleMouse.addPointer(location: const Offset(400, 300));
    await idleMouse.moveTo(const Offset(420, 320));
    await settle(tester, 0.5);
    expect(topOpacity(), 1);
    await idleMouse.removePointer();
    // The few top buttons; the rest is in "⋯".
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).last);
    await settle(tester, 1);
    await shot(tester, '06h1_desktop_more');
    expect(find.text('Диджей'), findsOneWidget);
    await tester.tap(find.text('Звук').last);
    await settle(tester, 1);
    if (find.text('Бас').evaluate().isEmpty) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .take(60)
          .join(' | ');
      // ignore: avoid_print
      print('DEBUG TEXTS: $texts');
    }
    await tester.tap(find.text('Бас'));
    await settle(tester, 1);
    await shot(tester, '06i_sound_sheet');
    await tester.tapAt(const Offset(5, 300));
    await settle(tester, 1);
    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 0.3);
    await shot(tester, '06h1_lyrics_closing');
    await settle(tester, 1.5);
    await shot(tester, '06h2_lyrics_closed');
    // Volume pops up right above the speaker on hover.
    final speaker = find.byType(HoverVolume);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(speaker));
    await settle(tester, 0.5);
    await shot(tester, '06h3_volume_hover');
    final pop = tester.getRect(find.byType(RotatedBox).last);
    final icon = tester.getRect(speaker);
    expect((pop.center.dx - icon.center.dx).abs(), lessThan(4));
    expect(pop.bottom, lessThan(icon.top));
    expect(icon.top - pop.bottom, lessThan(40));
    // Changing the volume on the popup keeps it open while the mouse is
    // still on it.
    final slider = find.descendant(
      of: find.byType(RotatedBox).last,
      matching: find.byType(Slider),
    );
    final sliderRect = tester.getRect(slider);
    await mouse.moveTo(sliderRect.center);
    await settle(tester, 0.3);
    await mouse.down(sliderRect.center);
    await mouse.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 50));
    await mouse.up();
    await settle(tester, 1);
    expect(find.byType(RotatedBox), findsOneWidget);
    // Gone as soon as the pointer leaves, as in Yandex Music.
    await mouse.moveTo(Offset.zero);
    await settle(tester, 0.3);
    expect(find.byType(RotatedBox), findsNothing);
    await mouse.removePointer();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await settle(tester, 1);

    // The bar at the bottom: a click on the wave seeks and stays; a click
    // on the bar's empty space opens the full player.
    {
      final bar = find.byType(MiniPlayer);
      final wave = find.descendant(
        of: bar,
        matching: find.byType(WavyProgress),
      );
      final w = tester.getRect(wave);
      await tester.tapAt(Offset(w.left + w.width * 0.8, w.center.dy));
      await settle(tester, 1);
      expect(find.byType(NowPlayingScreen), findsNothing);
      final b = tester.getRect(bar);
      // Between the transport and the queue button: nothing but the bar.
      await tester.tapAt(Offset(b.left + b.width * 0.72, b.top + 22));
      await settle(tester, 2);
      expect(find.byType(NowPlayingScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await settle(tester, 1);
    }

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
    // A mouse moves the releases row: ‹ › on hover, and dragging.
    {
      final page = find
          .descendant(
            of: find.byType(ArtistScreen),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final title = find.text('Релизы');
      await tester.scrollUntilVisible(title, 300, scrollable: page);
      await settle(tester, 1);
      final row = find
          .descendant(
            of: find.byType(ArtistScreen),
            matching: find.byType(HScroll),
          )
          .first;
      final list = find.descendant(of: row, matching: find.byType(Scrollable));
      double offset() =>
          tester.state<ScrollableState>(list.first).position.pixels;
      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: Offset.zero);
      await m.moveTo(tester.getCenter(row));
      await settle(tester, 0.5);
      await shot(tester, '07b0_artist_row_hover');
      // ♥ on an album: it's in Library → Albums.
      await m.moveTo(Offset.zero);
      await tester.tap(
        find.descendant(of: row, matching: find.byType(PressScale)).first,
      );
      await settle(tester, 4);
      await tester.tap(find.byKey(const ValueKey('save-album')));
      await settle(tester, 1);
      await shot(tester, '07b01_album_saved');
      expect(library.saved('album'), hasLength(1));
      Navigator.of(tester.element(find.byType(AlbumScreen))).pop();
      await settle(tester, 1);
      await m.moveTo(tester.getCenter(row));
      await settle(tester, 0.5);
      await tester.tap(find.byKey(const ValueKey('hscroll-forward')).first);
      await settle(tester, 1);
      final paged = offset();
      expect(paged, greaterThan(0));
      // Dragging with the mouse button held, as on a PC without a trackpad.
      await m.moveTo(tester.getCenter(row) - const Offset(0, 40));
      await m.down(tester.getCenter(row) - const Offset(0, 40));
      for (var i = 0; i < 10; i++) {
        await m.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await m.up();
      await settle(tester, 1);
      expect(offset(), lessThan(paged));
      await m.removePointer();
      await tester.scrollUntilVisible(
        find.text('Волна артиста'),
        -300,
        scrollable: page,
      );
      await settle(tester, 1);
    }
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
    // Back in search with an empty field: what was searched and opened.
    Navigator.of(tester.element(find.byType(ArtistScreen))).pop();
    await settle(tester, 1);
    await tester.tap(find.byTooltip('Очистить'));
    await settle(tester, 1);
    await shot(tester, '07b1_search_history');
    expect(find.text('Вы искали'), findsOneWidget);
    expect(find.text('miyagi'), findsWidgets);
    // The saved album is in Library → Albums.
    await tester.tap(find.text('Библиотека').first);
    await settle(tester, 1);
    await tester.tap(find.text('Альбомы'));
    await settle(tester, 2);
    await shot(tester, '04d_library_albums');
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.text('Любимые').first);
    await settle(tester, 1);
    await tester.tap(find.text('Главная').first);
    await settle(tester, 3);
    await shot(tester, '07d_home_wave_charts');
    // Ready-made collections: open the first one.
    for (var i = 0; i < 8 && find.text('Подборки').evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(1000, 600), const Offset(0, -400));
      await settle(tester, 0.5);
    }
    await tester.ensureVisible(find.text('Подборки'));
    await settle(tester, 4);
    final mixCard = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mix-'),
    );
    expect(mixCard, findsWidgets);
    await tester.ensureVisible(mixCard.first);
    await settle(tester, 1);
    await shot(tester, '07d1_home_mixes');
    await tester.tap(mixCard.first);
    await settle(tester, 5);
    await shot(tester, '07d2_mix');
    Navigator.of(tester.element(find.byType(MixScreen))).pop();
    await settle(tester, 1);
    // Back to the top of Home.
    for (var i = 0; i < 10 && find.text('Настроить').evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(1000, 300), const Offset(0, 500));
      await settle(tester, 0.5);
    }
    await tester.ensureVisible(find.text('Настроить'));
    await settle(tester, 1);
    await tester.tap(find.text('Настроить'));
    await settle(tester, 1);
    // In the sheet (the radios on the home screen have the same words).
    await tester.tap(find.text('Грустное').last);
    await tester.tap(find.text('Русский').last);
    await settle(tester, 1);
    await shot(tester, '07e_wave_settings');
    await tester.tap(find.text('Слушать'));
    await settle(tester, 10);
    await shot(tester, '07f_my_wave_playing');
    expect(handler.waveTitle.value, 'Моя волна');

    // Phone layout, in the classic player (another test device may have
    // shared its own look over the relay).
    ProviderScope.containerOf(tester.element(find.byType(SegueApp)))
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(playerStyle: PlayerStyle.classic));
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
    // Phone: the rarer buttons are in "⋯".
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).last);
    await settle(tester, 1);
    await shot(tester, '09b_phone_menu');
    expect(find.text('Диджей'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester, 1);

    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 5);
    await shot(tester, '10_phone_lyrics');
    await settle(tester, 0.7);
    await shot(tester, '10b_phone_lyrics');

    // The other look: the cover over the whole top.
    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 1);
    ProviderScope.containerOf(tester.element(find.byType(NowPlayingScreen)))
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(playerStyle: PlayerStyle.cover));
    await settle(tester, 3);
    await shot(tester, '11_phone_cover_player');
    expect(find.byType(CoverPlayer), findsOneWidget);
    // Lyrics open inside the same look.
    await tester.tap(find.byIcon(Icons.lyrics_rounded).last);
    await settle(tester, 3);
    await shot(tester, '11a_phone_cover_lyrics');
    expect(find.byType(CoverPlayer), findsOneWidget);
    tester.view.physicalSize = const Size(2400, 1500);
    tester.view.devicePixelRatio = 1.5;
    await settle(tester, 2);
    await shot(tester, '11b_desktop_cover_player');
    ProviderScope.containerOf(tester.element(find.byType(NowPlayingScreen)))
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(playerStyle: PlayerStyle.classic));
    await settle(tester, 1);

    expect(tester.takeException(), isNull);
    await handler.stop();
    binding.reportData = shots;
  }, timeout: const Timeout(Duration(minutes: 10)));
}
