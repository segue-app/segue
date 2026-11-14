// The DJ screen on a real (muted) mix: shots before and during the mix.
// flutter drive -d macos --driver test_driver/integration_test.dart
//   --target integration_test/dj_screen_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/dj/beat_service.dart';
import 'package:segue/core/library/library.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/settings/settings.dart';
import 'package:segue/core/sources/youtube_source.dart';
import 'package:segue/ui/screens/dj_screen.dart';
import 'package:segue/ui/theme/theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  final shots = <String, String>{};
  final boundary = GlobalKey();

  Future<void> shot(String name) async {
    final ro =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    shots[name] = base64Encode(bytes!.buffer.asUint8List());
  }

  Future<void> settle(WidgetTester tester, double seconds) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('dj screen', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final player = SegueAudioHandler({SourceKind.youtube: yt});
    await player.setVolume(0); // silent
    player
      ..fadeSeconds = 8
      ..beats = BeatService(uriFor: player.analysisUri);
    final library = LibraryStore.memory();
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWithValue(player),
        libraryProvider.overrideWithValue(library),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(theme: buildTheme(), home: const DjScreen()),
        ),
      ),
    );
    await tester.pump();
    container
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(fadeSeconds: 8, matchTempo: true));
    final a = (await yt.search(
      'Daft Punk Get Lucky official audio',
      limit: 1,
    )).first;
    final b = (await yt.search(
      'Billie Jean Michael Jackson official audio',
      limit: 1,
    )).first;
    await player.playList([a, b], 0);
    // Deck A must show the old song until the mix is over: never the new
    // one and back.
    final seen = <String>[];
    final watch = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final k = player.dj.outgoing?.key;
      if (k != null && (seen.isEmpty || seen.last != k)) seen.add(k);
    });
    await settle(tester, 10);
    await player.seek(
      player.mediaItem.value!.duration! - const Duration(seconds: 30),
    );
    await settle(tester, 3);
    await shot('dj_before');
    // How evenly the record turns: its angle on frames 16 ms apart.
    final steps = <double>[];
    double? last;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final ts = tester
          .widgetList<Transform>(find.byType(Transform))
          .where((t) => t.transform.storage[1].abs() > 1e-9);
      if (ts.isEmpty) continue;
      final m = ts.first.transform.storage;
      final a = math.atan2(m[1], m[0]);
      if (last != null) {
        var d = a - last;
        if (d < -math.pi) d += 2 * math.pi;
        steps.add(d);
      }
      last = a;
    }
    steps.sort();
    debugPrint(
      'DISC steps: n=${steps.length} min=${steps.first.toStringAsFixed(4)} '
      'median=${steps[steps.length ~/ 2].toStringAsFixed(4)} max=${steps.last.toStringAsFixed(4)}',
    );
    final zero = steps.where((d) => d.abs() < 1e-6).length;
    debugPrint('DISC frozen frames: $zero');
    await settle(tester, 9);
    await shot('dj_mixing');
    // A phone: both decks still side by side.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await settle(tester, 1);
    await shot('dj_phone');
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    await settle(tester, 4);
    await shot('dj_mixing2');
    // The moment the decks change songs: both slide, mid-way.
    final until = DateTime.now().add(const Duration(seconds: 8));
    while (player.dj.mixing && DateTime.now().isBefore(until)) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await shot('dj_swap');
    expect(player.index, 1);
    watch.cancel();
    debugPrint('DECK A order: ${seen.length} songs');
    expect(seen, [a.key, b.key]);
    // Swiped down from the top, it closes; a short pull springs back.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(DjScreen.route());
    await settle(tester, 1);
    expect(find.byType(DjScreen, skipOffstage: false), findsNWidgets(2));
    await tester.drag(find.byType(ListView).last, const Offset(0, 60));
    await settle(tester, 1);
    expect(find.byType(DjScreen, skipOffstage: false), findsNWidgets(2));
    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await settle(tester, 1);
    expect(find.byType(DjScreen, skipOffstage: false), findsOneWidget);
    debugPrint('PULL to close ok');
    await player.stop();
    binding.reportData = shots;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
