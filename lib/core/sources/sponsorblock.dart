import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the music itself is in a YouTube music video, from SponsorBlock's
/// community data ("music_offtopic": spoken intros, skits, end cards).
class SponsorBlock {
  SponsorBlock({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _cache = <String, ({Duration? start, Duration? end})>{};

  /// Start of the music (when a video opens with a non-music part) and its
  /// end (when it closes with one). Nulls when the video has none.
  Future<({Duration? start, Duration? end})> musicBounds(String videoId) async {
    final hit = _cache[videoId];
    if (hit != null) return hit;
    ({Duration? start, Duration? end}) bounds = (start: null, end: null);
    try {
      final res = await _http
          .get(
            Uri.parse(
              'https://sponsor.ajay.app/api/skipSegments'
              '?videoID=${Uri.encodeQueryComponent(videoId)}'
              '&category=music_offtopic',
            ),
          )
          .timeout(const Duration(seconds: 4));
      // 404 means "no segments": the whole video is music.
      if (res.statusCode == 200) bounds = parse(res.body);
    } catch (_) {
      return bounds; // not cached: try again next time
    }
    _cache[videoId] = bounds;
    return bounds;
  }

  /// Exposed for tests.
  static ({Duration? start, Duration? end}) parse(String body) {
    Duration? start, end;
    for (final s in (jsonDecode(body) as List).cast<Map>()) {
      final seg = (s['segment'] as List).cast<num>();
      final total = (s['videoDuration'] as num?)?.toDouble() ?? 0;
      final a = seg[0].toDouble(), b = seg[1].toDouble();
      // Only what touches the very start or end; skits in the middle stay.
      if (a < 3 && b < 120) {
        start = Duration(milliseconds: (b * 1000).round());
      } else if (total > 0 && b > total - 3 && total - a < 180) {
        end = Duration(milliseconds: (a * 1000).round());
      }
    }
    return (start: start, end: end);
  }
}
