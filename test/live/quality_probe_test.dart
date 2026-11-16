// Normal vs high quality YouTube audio, from this machine (network required).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  test('normal and high quality streams', () async {
    final yt = YouTubeSource();
    await yt.warmUp();
    for (final id in ['4NRXx6U8ABQ', 'fHI8X4OXluQ', 'kJQP7kiw5Fk']) {
      final t = Track(id: id, source: SourceKind.youtube, title: id, artist: '');
      for (final high in [false, true]) {
        yt.highQuality = high;
        final sw = Stopwatch()..start();
        final info = await yt.resolveDirect(t);
        final ms = sw.elapsedMilliseconds;
        final kbps = info.contentLength != null && info.duration != null
            ? info.contentLength! * 8 / info.duration!.inMilliseconds
            : null;
        // The last megabyte is served too: the whole song plays.
        var tail = 'hls';
        if (!info.hls && info.contentLength != null) {
          final end = info.contentLength! - 1;
          final r = await http.get(
            info.url,
            headers: {'Range': 'bytes=${end - 1023}-$end'},
          );
          tail = '${r.statusCode}';
          expect(r.statusCode, 206);
        }
        // ignore: avoid_print
        print('$id ${high ? 'high  ' : 'normal'} ${info.hls ? 'HLS AAC' : info.mimeType} '
            '${kbps?.toStringAsFixed(0) ?? '128'} kbps, ready in $ms ms, tail $tail');
        if (high) expect(info.mimeType, contains('webm'));
      }
    }
    final file = await yt.resolveFile(
      const Track(id: '4NRXx6U8ABQ', source: SourceKind.youtube, title: 'x', artist: ''),
    );
    print('download: ${file.mimeType}'); // ignore: avoid_print
  }, timeout: const Timeout(Duration(minutes: 3)));
}
