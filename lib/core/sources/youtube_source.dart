import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/track.dart';
import 'music_source.dart';

/// YouTube search (youtube_explode_dart) and audio streams.
///
/// Streams come from YouTube's internal player API using the visionOS client
/// (the same approach yt-dlp uses), because most other clients now get
/// only the first ~1 MB of a file without a PO token. youtube_explode's
/// clients stay as a fallback.
class YouTubeSource implements MusicSource, FileSource {
  YouTubeSource() : _client = yt.YoutubeExplode();

  final yt.YoutubeExplode _client;
  final _http = http.Client();

  @override
  SourceKind get kind => SourceKind.youtube;

  @override
  String get label => 'YouTube';

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final yt.VideoSearchList results;
    try {
      results = await _client.search.search(query);
    } on Error catch (e) {
      // The library's page parser throws Errors when YouTube changes its
      // markup; surface them as a normal failure instead of a crash.
      throw StateError('YouTube search is temporarily unavailable ($e)');
    }
    return results
        .where((v) => !v.isLive)
        .take(limit)
        .map(
          (v) => Track(
            id: v.id.value,
            source: kind,
            title: v.title,
            artist: _cleanArtist(v.author),
            // hq720 is 16:9 without the black letterbox bars that the
            // 4:3 "high" thumbnail has; Artwork falls back if it's missing.
            artworkUrl: 'https://i.ytimg.com/vi/${v.id.value}/hq720.jpg',
            duration: v.duration,
          ),
        )
        .toList();
  }

  @override
  Future<StreamInfo> resolveStream(Track track) => _resolve(track, hls: true);

  /// A whole .m4a file for downloading (HLS is for streaming only).
  @override
  Future<StreamInfo> resolveFile(Track track) => _resolve(track, hls: false);

  Future<StreamInfo> _resolve(Track track, {required bool hls}) async {
    final errors = <String>[];
    for (final resolver in [
      (String id) => _visionOs(id, hls: hls),
      _explodeFallback,
    ]) {
      try {
        final info = await resolver(track.id);
        if (await _servesWholeFile(info)) return info;
        errors.add('stream rejected');
      } catch (e) {
        errors.add('$e'.split('\n').first);
      }
    }
    throw StateError('No playable YouTube stream for ${track.title}: $errors');
  }

  // --- visionOS player API --------------------------------------------------

  static const _visionUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  /// Visitor id from the YouTube watch page, as a browser would have it.
  /// Requests without one are far more likely to hit the bot check.
  String? _visitorData;
  DateTime _visitorAt = DateTime(0);

  /// Fetches the visitor id in advance, so the first track after launch
  /// doesn't wait for the watch page.
  Future<void> warmUp() => _visitor('jNQXAC9IVRw');

  Future<String?> _visitor(String videoId) async {
    if (_visitorData != null &&
        DateTime.now().difference(_visitorAt) < const Duration(hours: 1)) {
      return _visitorData;
    }
    try {
      final page = await _http
          .get(
            Uri.parse(
              'https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&has_verified=1',
            ),
            headers: {
              'User-Agent': _visionUa,
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 12));
      final m = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(page.body);
      if (m != null) {
        _visitorData = m.group(1);
        _visitorAt = DateTime.now();
      }
    } catch (_) {}
    return _visitorData;
  }

  Future<StreamInfo> _visionOs(String videoId, {bool hls = true}) async {
    final visitor = await _visitor(videoId);
    final res = await _http
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
          ),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _visionUa,
            'Origin': 'https://www.youtube.com',
            'X-YouTube-Client-Name': '101',
            'X-YouTube-Client-Version': '1.02',
            'X-Goog-Visitor-Id': ?visitor,
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'VISIONOS',
                'clientVersion': '1.02',
                'deviceMake': 'Apple',
                'deviceModel': 'RealityDevice17,1',
                'osName': 'visionOS',
                'osVersion': '26.5.23O471',
                'hl': 'en',
                'gl': 'US',
                'visitorData': ?visitor,
              },
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw StateError('player ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final status = data['playabilityStatus'] as Map<String, dynamic>?;
    if (status?['status'] != 'OK') {
      throw StateError('unplayable: ${status?['reason'] ?? status?['status']}');
    }
    final streaming = data['streamingData'] as Map<String, dynamic>? ?? {};
    final duration = _approxDuration(streaming);

    // Best option: the audio-only HLS rendition. Every platform player
    // handles HLS natively, with exact duration and seeking.
    final hlsUrl = hls ? streaming['hlsManifestUrl'] as String? : null;
    if (hlsUrl != null) {
      final audio = await _hlsAudioPlaylist(hlsUrl);
      if (audio != null) {
        return StreamInfo(audio, hls: true, duration: duration);
      }
    }

    final formats =
        ((data['streamingData'] as Map?)?['adaptiveFormats'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .where(
              (f) =>
                  f['url'] != null &&
                  (f['mimeType'] as String? ?? '').startsWith('audio/'),
            )
            .toList();
    if (formats.isEmpty) throw StateError('no audio formats');
    // Prefer AAC/MP4: it plays everywhere, including iOS and macOS.
    final mp4 = formats.where(
      (f) => (f['mimeType'] as String).startsWith('audio/mp4'),
    );
    final pool = (mp4.isNotEmpty ? mp4 : formats).toList()
      ..sort(
        (a, b) =>
            (b['bitrate'] as int? ?? 0).compareTo(a['bitrate'] as int? ?? 0),
      );
    final best = pool.first;
    return StreamInfo(
      Uri.parse(best['url'] as String),
      contentLength: int.tryParse('${best['contentLength']}'),
      mimeType: (best['mimeType'] as String).split(';').first,
      chunked: true,
      duration: duration,
    );
  }

  static Duration? _approxDuration(Map<String, dynamic> streaming) {
    for (final f in (streaming['adaptiveFormats'] as List? ?? [])) {
      final ms = int.tryParse('${(f as Map)['approxDurationMs']}');
      if (ms != null) return Duration(milliseconds: ms);
    }
    return null;
  }

  /// Picks the audio-only playlist from a YouTube HLS master playlist:
  /// itag 234 is AAC 128 kbps, 233 is a low-bitrate fallback.
  Future<Uri?> _hlsAudioPlaylist(String masterUrl) async {
    try {
      final res = await _http
          .get(Uri.parse(masterUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final byGroup = <String, String>{};
      for (final line in res.body.split('\n')) {
        if (!line.startsWith('#EXT-X-MEDIA:') || !line.contains('TYPE=AUDIO')) {
          continue;
        }
        final group = RegExp(r'GROUP-ID="([^"]+)"').firstMatch(line)?.group(1);
        final uri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        if (group != null && uri != null) byGroup[group] = uri;
      }
      final pick =
          byGroup['234'] ?? byGroup['233'] ?? byGroup.values.firstOrNull;
      return pick == null ? null : Uri.parse(pick);
    } catch (_) {
      return null;
    }
  }

  // --- youtube_explode fallback ---------------------------------------------

  static final _fallbackClients = [
    yt.YoutubeApiClient.android,
    yt.YoutubeApiClient.ios,
    yt.YoutubeApiClient.androidVr,
  ];

  Future<StreamInfo> _explodeFallback(String id) async {
    for (final client in _fallbackClients) {
      try {
        final manifest = await _client.videos.streams.getManifest(
          id,
          ytClients: [client],
        );
        final audio = manifest.audioOnly;
        if (audio.isEmpty) continue;
        final mp4 = audio.where((s) => s.container == yt.StreamContainer.mp4);
        final s = (mp4.isNotEmpty ? mp4 : audio).withHighestBitrate();
        final info = StreamInfo(
          s.url,
          contentLength: s.size.totalBytes,
          mimeType: s.codec.mimeType,
          chunked: true,
        );
        if (await _servesWholeFile(info)) return info;
      } catch (_) {}
    }
    throw StateError('fallback clients exhausted');
  }

  /// Many clients serve only the start of a file, so probe near the end too.
  Future<bool> _servesWholeFile(StreamInfo info) async {
    if (info.hls) return true; // playlist was just fetched successfully
    final len = info.contentLength;
    final probes = [0, if (len != null && len > 2000000) len - 200000];
    for (final start in probes) {
      try {
        final res = await _http
            .get(info.url, headers: {'Range': 'bytes=$start-${start + 1023}'})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200 && res.statusCode != 206) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Official artist channels end with " - Topic".
  static String _cleanArtist(String author) => author.endsWith(' - Topic')
      ? author.substring(0, author.length - 8)
      : author;

  void dispose() {
    _client.close();
    _http.close();
  }
}
