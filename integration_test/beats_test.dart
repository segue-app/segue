// Beat analysis on real songs: decode a stretch with libmpv (no sound, it
// writes samples to a file) and find the tempo and the beats.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:segue/core/dj/beat_grid.dart';
import 'package:segue/core/dj/pcm_decoder.dart';
import 'package:segue/core/player/player_handler.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tempo and beats of real songs', (tester) async {
    MediaKit.ensureInitialized();
    final yt = YouTubeSource();
    final decoder = PcmDecoder();
    // Known tempos (rounded, as published).
    for (final (query, bpm) in [
      ('Ed Sheeran Shape of You official', 96.0),
      ('Daft Punk Get Lucky official audio', 116.0),
      ('The Weeknd Blinding Lights official audio', 171.0),
      ('Billie Jean Michael Jackson official audio', 117.0),
    ]) {
      final t = (await yt.search(query, limit: 1)).first;
      final info = await yt.resolveStream(t);
      final uri = Uri.parse(await SegueAudioHandler.playableUri(info));
      final sw = Stopwatch()..start();
      final pcm = await decoder.decode(
        uri,
        start: const Duration(seconds: 60),
        length: const Duration(seconds: 40),
      );
      final decoded = sw.elapsedMilliseconds;
      expect(pcm, isNotNull, reason: query);
      final g = analyzeBeats(pcm!, PcmDecoder.sampleRate, offset: 60)!;
      // ignore: avoid_print
      print('BEATS ${t.title}: $g, decoded ${pcm.length / PcmDecoder.sampleRate}s '
          'in ${decoded}ms, analysed in ${sw.elapsedMilliseconds - decoded}ms');
      final ratio = g.bpm / bpm;
      // Half or double counts the same beats.
      final folded = ratio < 0.75 ? ratio * 2 : (ratio > 1.5 ? ratio / 2 : ratio);
      expect(folded, closeTo(1, 0.02), reason: '$query: $g');
    }
    await decoder.dispose();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
