import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_visibility.dart';
import 'core/import/library_import.dart';
import 'core/catalog/taste.dart';
import 'core/downloads/audio_cache.dart';
import 'core/models/track.dart';
import 'core/player/player.dart';
import 'core/player/trims.dart';
import 'core/catalog/deezer.dart';
import 'core/catalog/wave.dart';
import 'core/downloads/downloads.dart';
import 'core/downloads/download_manager.dart';
import 'core/import/import.dart';
import 'core/integrations/discord.dart';
import 'core/integrations/home_widgets.dart';
import 'core/integrations/lastfm.dart';
import 'core/local/local_library.dart';
import 'core/import/playlist_importer.dart';
import 'core/sources/match_source.dart';
import 'core/settings/settings.dart';
import 'core/sync/connect.dart';
import 'core/sync/jam.dart';
import 'core/sync/relay.dart';
import 'core/sync/sync.dart';
import 'core/sync/sync_service.dart';
import 'core/sources/music_source.dart';
import 'core/sources/soundcloud_source.dart';
import 'core/sources/sponsorblock.dart';
import 'core/sources/sources.dart';
import 'core/sources/youtube_source.dart';
import 'core/library/library.dart';
import 'core/library/library_store.dart';
import 'ui/screens/shell.dart';
import 'ui/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppVisibility.attach();

  final soundcloud = SoundCloudSource();
  final youtube = YouTubeSource();
  unawaited(youtube.warmUp());
  final match = MatchSource(youtube);
  final Map<SourceKind, MusicSource> sources = {
    SourceKind.soundcloud: soundcloud,
    SourceKind.youtube: youtube,
    SourceKind.match: match,
    SourceKind.local: LocalSource(),
  };
  final handler = await initPlayer(sources);
  final library = await LibraryStore.open();
  handler.onTrackStarted = library.recordPlay;
  final downloads = DownloadManager(library: library, sources: sources);
  // Recently played songs kept on the device: instant start, offline.
  final audioCache = AudioCache(
    library: library,
    downloads: downloads,
    sources: sources,
  )..attach(handler);
  handler.localPathFor = (t) =>
      library.downloadedPath(t) ?? audioCache.pathFor(t);
  // Loudness of tracks played before, for files that don't carry it.
  final loudness = <String, dynamic>{};
  try {
    loudness.addAll(
      jsonDecode(library.getMeta('loudness') ?? '{}') as Map<String, dynamic>,
    );
  } catch (_) {}
  Timer? saveLoudness;
  handler.storedLoudness = (t) => (loudness[t.key] as num?)?.toDouble();
  handler.saveLoudness = (t, db) {
    if (loudness[t.key] == db) return;
    loudness[t.key] = db;
    while (loudness.length > 3000) {
      loudness.remove(loudness.keys.first);
    }
    saveLoudness?.cancel();
    saveLoudness = Timer(
      const Duration(seconds: 3),
      () => library.setMeta('loudness', jsonEncode(loudness)),
    );
  };
  handler.seekableCopy = downloads.seekableCopy;
  final catalog = Catalog();
  final localLibrary = LocalLibrary(library);
  // Re-open saved music folders and pick up new files, in the background.
  unawaited(
    localLibrary.start().catchError((Object e) => debugPrint('local: $e')),
  );
  // YouTube matches are remembered, so a song found once starts without
  // searching again.
  final matches = <String, dynamic>{};
  try {
    matches.addAll(
      jsonDecode(library.getMeta('matches2') ?? '{}') as Map<String, dynamic>,
    );
  } catch (_) {}
  Timer? saveMatches;
  match.recall = (key) {
    final j = matches[key];
    return j == null
        ? null
        : Track.fromJson((j as Map).cast<String, dynamic>());
  };
  // Imported songs come without covers: the album's from Deezer (sharp,
  // square), the video thumbnail meanwhile or if Deezer doesn't have it.
  Future<void> realCover(Track t) async {
    final url = await catalog
        .cover(t.artist, MatchSource.coreTitle(t.title), length: t.duration)
        .catchError((Object _) => null);
    if (url != null) library.fillArtwork(t, url);
  }

  match.onMatched = (imported, found) {
    if (found.artworkUrl != null) {
      library.fillArtwork(imported, found.artworkUrl!);
    }
    unawaited(realCover(imported));
    matches[imported.key] = found.toJson();
    while (matches.length > 2000) {
      matches.remove(matches.keys.first);
    }
    saveMatches?.cancel();
    saveMatches = Timer(
      const Duration(seconds: 3),
      () => library.setMeta('matches2', jsonEncode(matches)),
    );
  };
  // Old Spotify imports stored artist links instead of names: fix them
  // and let those songs be found again.
  unawaited(
    LibraryImporter.fixSpotifyArtists(library)
        .then((fixed) {
          if (fixed.isEmpty) return;
          for (final k in fixed.keys) {
            matches.remove(k);
            match.forget(k);
          }
          library.setMeta('matches2', jsonEncode(matches));
          handler.updateTracks(fixed);
          debugPrint('fixed ${fixed.length} imported artists');
        })
        .catchError((Object e) => debugPrint('fix artists: $e')),
  );
  // Songs imported earlier still show video thumbnails: swap in album
  // covers, a few at a time, in the background.
  unawaited(() async {
    // Each song is looked up once (Deezer may not have it at all).
    final checked = <String>{
      ...(jsonDecode(library.getMeta('covers_checked') ?? '[]') as List)
          .cast<String>(),
    };
    final thumbs = [
      for (final t in library.tracksWithArtworkPrefix('https://i.ytimg.com/'))
        if (!checked.contains(t.key)) t,
    ];
    for (var i = 0; i < thumbs.length && i < 400; i += 4) {
      final batch = thumbs.skip(i).take(4).toList();
      await Future.wait([for (final t in batch) realCover(t)]);
      checked.addAll(batch.map((t) => t.key));
      library.setMeta('covers_checked', jsonEncode(checked.toList()));
    }
  }().catchError((Object e) => debugPrint('covers: $e')));
  // Handoffs carry the exact YouTube version of imported songs.
  handler.matchOf = match.matched;
  handler.adoptMatch = (imported, version) {
    if (match.matched(imported)?.id != version.id) {
      match.choose(imported, version);
    }
  };
  final lastFm = LastFm(library)..attach(handler);
  // My wave learns from how you listen.
  final taste = Taste(library);
  handler.onTrackLeft = (t, played, length, skipped) {
    taste.record(t, played, length, skipped);
    // In the wave, an artist you keep skipping leaves the queue at once.
    if (handler.waveTitle.value != null && taste.artist(t.artist) <= -3) {
      final a = Taste.norm(t.artist);
      handler.removeUpcomingWhere((x) => Taste.norm(x.artist) == a);
    }
  };
  DiscordPresence().attach(handler);
  final trims = TrimStore(library);
  handler.trimFor = (t) {
    final trim = trims.of(t);
    return trim == null ? null : (start: trim.start, end: trim.end);
  };
  // DJ mix: where the music is in music videos (SponsorBlock) and tempos.
  final sponsorBlock = SponsorBlock();
  handler.autoBounds = (t) async {
    final id = switch (t.source) {
      SourceKind.youtube => t.id,
      SourceKind.match => match.matched(t)?.id,
      _ => null,
    };
    return id == null ? null : sponsorBlock.musicBounds(id);
  };
  handler.bpmFor = (t) => catalog.bpm(t.artist, t.title);
  HomeWidgets(handler).attach();
  // Player preferences.
  handler.setVolume(double.tryParse(library.getMeta('volume') ?? '') ?? 1);
  final importer = PlaylistImporter()..soundcloudClientId = soundcloud.clientId;
  final sync = SyncService(library: library, player: handler);
  // Local network sync must never block the app from opening.
  final relay = Relay(
    library: library,
    player: handler,
    deviceName: () => sync.deviceName,
  );
  final connect = Connect(
    sync: sync,
    relay: relay,
    library: library,
    player: handler,
  );
  final jam = JamService(
    player: handler,
    deviceId: library.deviceId,
    name: () => sync.deviceName,
  );
  // Local network first (it also finds out this device's name), then the
  // internet relay. Neither may block the app from opening.
  unawaited(sync.start().catchError((Object e) => debugPrint('sync off: $e')));
  // The relay doesn't wait for Bonjour (which can hang on some networks),
  // only for this device's name, and not for long.
  unawaited(
    () async {
      for (var i = 0; i < 30 && !sync.ready.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await relay.start();
    }().catchError((Object e) => debugPrint('relay off: $e')),
  );

  runApp(
    ProviderScope(
      overrides: [
        sourcesProvider.overrideWithValue(sources),
        playerProvider.overrideWithValue(handler),
        libraryProvider.overrideWithValue(library),
        importerProvider.overrideWithValue(importer),
        syncProvider.overrideWithValue(sync),
        connectProvider.overrideWithValue(connect),
        jamProvider.overrideWithValue(jam),
        downloadsProvider.overrideWithValue(downloads),
        audioCacheProvider.overrideWithValue(audioCache),
        catalogProvider.overrideWithValue(catalog),
        waveProvider.overrideWithValue(
          Wave(catalog, library, handler, taste: taste),
        ),
        tasteProvider.overrideWithValue(taste),
        localLibraryProvider.overrideWithValue(localLibrary),
        lastFmProvider.overrideWithValue(lastFm),
        trimStoreProvider.overrideWithValue(trims),
      ],
      // Out of sight, nothing animates (each frame would be drawn for
      // nobody); it all resumes where it was.
      child: ValueListenableBuilder<bool>(
        valueListenable: AppVisibility.visibleNotifier,
        builder: (_, visible, child) =>
            TickerMode(enabled: visible, child: child!),
        child: const SegueApp(),
      ),
    ),
  );
}

class SegueApp extends ConsumerWidget {
  const SegueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Segue',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(font: settings.font),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(settings.textScale),
            disableAnimations: settings.reduceMotion || mq.disableAnimations,
          ),
          child: child!,
        );
      },
      home: const Shell(),
    );
  }
}
