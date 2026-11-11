import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/track.dart';
import 'core/player/player.dart';
import 'core/player/trims.dart';
import 'core/catalog/deezer.dart';
import 'core/catalog/wave.dart';
import 'core/downloads/downloads.dart';
import 'core/downloads/download_manager.dart';
import 'core/import/import.dart';
import 'core/integrations/discord.dart';
import 'core/integrations/lastfm.dart';
import 'core/local/local_library.dart';
import 'core/import/playlist_importer.dart';
import 'core/sources/match_source.dart';
import 'core/settings/settings.dart';
import 'core/sync/connect.dart';
import 'core/sync/relay.dart';
import 'core/sync/sync.dart';
import 'core/sync/sync_service.dart';
import 'core/sources/music_source.dart';
import 'core/sources/soundcloud_source.dart';
import 'core/sources/sources.dart';
import 'core/sources/youtube_source.dart';
import 'core/library/library.dart';
import 'core/library/library_store.dart';
import 'ui/screens/shell.dart';
import 'ui/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
  handler.localPathFor = library.downloadedPath;
  final downloads = DownloadManager(library: library, sources: sources);
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
      jsonDecode(library.getMeta('matches') ?? '{}') as Map<String, dynamic>,
    );
  } catch (_) {}
  Timer? saveMatches;
  match.recall = (key) {
    final j = matches[key];
    return j == null
        ? null
        : Track.fromJson((j as Map).cast<String, dynamic>());
  };
  match.onMatched = (imported, found) {
    if (found.artworkUrl != null) {
      library.fillArtwork(imported, found.artworkUrl!);
    }
    matches[imported.key] = found.toJson();
    while (matches.length > 2000) {
      matches.remove(matches.keys.first);
    }
    saveMatches?.cancel();
    saveMatches = Timer(
      const Duration(seconds: 3),
      () => library.setMeta('matches', jsonEncode(matches)),
    );
  };
  final lastFm = LastFm(library)..attach(handler);
  DiscordPresence().attach(handler);
  final trims = TrimStore(library);
  handler.trimFor = (t) {
    final trim = trims.of(t);
    return trim == null ? null : (start: trim.start, end: trim.end);
  };
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
  final connect = Connect(sync: sync, relay: relay, library: library);
  // Local network first (it also finds out this device's name), then the
  // internet relay. Neither may block the app from opening.
  unawaited(
    sync
        .start()
        .catchError((Object e) => debugPrint('sync off: $e'))
        .then((_) => relay.start())
        .catchError((Object e) => debugPrint('relay off: $e')),
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
        downloadsProvider.overrideWithValue(downloads),
        catalogProvider.overrideWithValue(catalog),
        waveProvider.overrideWithValue(Wave(catalog, library, handler)),
        localLibraryProvider.overrideWithValue(localLibrary),
        lastFmProvider.overrideWithValue(lastFm),
        trimStoreProvider.overrideWithValue(trims),
      ],
      child: const SegueApp(),
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
