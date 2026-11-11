import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart';

import '../models/track.dart';
import '../sources/music_source.dart';
import 'player_handler.dart';

/// Set in main() before runApp, after the handler is created.
final playerProvider = Provider<SegueAudioHandler>(
  (ref) => throw UnimplementedError('playerProvider is overridden in main()'),
);

/// Creates the audio handler (libmpv via media_kit on every platform).
/// On Android, iOS and macOS it is registered with the OS media controls.
Future<SegueAudioHandler> initPlayer(
  Map<SourceKind, MusicSource> sources,
) async {
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) return SegueAudioHandler(sources);
  // Music session: keeps playing in the background on iOS, ducks for calls.
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {}
  return AudioService.init(
    builder: () => SegueAudioHandler(sources),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'fm.segue.audio',
      androidNotificationChannelName: 'Segue',
      androidNotificationOngoing: true,
    ),
  );
}

final currentTrackProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(playerProvider).mediaItem,
);

final playingProvider = StreamProvider<bool>(
  (ref) => ref.watch(playerProvider).playingStream,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(playerProvider).positionStream,
);

final durationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(playerProvider).durationStream,
);
