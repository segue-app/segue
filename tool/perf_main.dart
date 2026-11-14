// CPU of the always-moving parts of the player, one scene at a time.
//
//   flutter build macos --profile -t tool/perf_main.dart
//   tool/perf_run.sh            (runs it and prints CPU per scene)
//
// Each scene prints `PERF|name|startMs|endMs`; the script reads the
// process's CPU time over that span.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/app_visibility.dart';
import 'package:segue/core/library/library.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/lyrics/lyrics.dart';
import 'package:segue/core/lyrics/translate.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/ui/theme/theme.dart';
import 'package:segue/ui/widgets/living_backdrop.dart';
import 'package:segue/ui/widgets/lyrics_view.dart';
import 'package:segue/ui/widgets/wavy_progress.dart';

const _track = Track(
  id: 'perf',
  source: SourceKind.youtube,
  title: 'Perf',
  artist: 'Segue',
);

/// A song of 60 lines, every word timed, a line every 3 s.
Lyrics _lyrics() {
  const text = 'every word you sing comes back to me tonight';
  final words = text.split(' ');
  return Lyrics(
    synced: true,
    lines: [
      for (var i = 0; i < 60; i++)
        LyricLine(
          Duration(seconds: 3 * i),
          text,
          words: [
            for (var w = 0; w < words.length; w++)
              LyricWord(
                words[w],
                Duration(milliseconds: 3000 * i + 300 * w),
                Duration(milliseconds: 3000 * i + 300 * w + 280),
              ),
          ],
        ),
    ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  AppVisibility.debugAlwaysActive = true;
  final clock = Stopwatch()..start();
  final position = Stream<Duration>.periodic(
    const Duration(milliseconds: 200),
    (_) => clock.elapsed,
  ).asBroadcastStream();
  final scene = ValueNotifier('idle');
  runApp(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWithValue(LibraryStore.memory()),
        playerProvider.overrideWithValue(SegueAudioHandler(const {})),
        positionProvider.overrideWith((ref) => position),
        playingProvider.overrideWith((ref) => Stream.value(true)),
        lyricsProvider.overrideWith((ref, t) async => _lyrics()),
        lyricsTranslationProvider.overrideWith((ref, t) async => null),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: ValueListenableBuilder<String>(
          valueListenable: scene,
          builder: (context, s, _) => Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (s != 'idle')
                  const RepaintBoundary(
                    child: LivingBackdrop(
                      palette: [
                        Color(0xFFFF9A76),
                        Color(0xFF7B5CFF),
                        Color(0xFFE0457B),
                        Color(0xFF2B6CB0),
                      ],
                      base: Color(0xFF15121A),
                      playing: true,
                    ),
                  ),
                if (s == 'lyrics')
                  const Padding(
                    padding: EdgeInsets.fromLTRB(420, 40, 40, 40),
                    child: LyricsView(track: _track),
                  ),
                if (s == 'progress')
                  Center(
                    child: SizedBox(
                      width: 500,
                      child: WavyProgress(
                        progress: 0.4,
                        playing: true,
                        color: SegueColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // Let the window appear and settle.
  await Future<void>.delayed(const Duration(seconds: 4));
  for (final name in ['idle', 'backdrop', 'progress', 'lyrics']) {
    scene.value = name;
    await Future<void>.delayed(const Duration(seconds: 3));
    final start = DateTime.now().millisecondsSinceEpoch;
    await Future<void>.delayed(const Duration(seconds: 12));
    final end = DateTime.now().millisecondsSinceEpoch;
    // ignore: avoid_print
    print('PERF|$name|$start|$end');
  }
  // ignore: avoid_print
  print('PERF|done|0|0');
  exit(0);
}
