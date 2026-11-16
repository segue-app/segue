import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/track.dart';
import 'music_source.dart';
import 'yt_mirrors.dart';

/// YouTube search and audio streams.
///
/// Streams come from YouTube's internal player API using the visionOS client
/// (the same approach yt-dlp uses), because most other clients now get
/// only the first ~1 MB of a file without a PO token. youtube_explode's
/// clients stay as a fallback.
class YouTubeSource implements MusicSource, FileSource {
  YouTubeSource() : _client = yt.YoutubeExplode();

  final yt.YoutubeExplode _client;
  final _http = http.Client();

  /// Public mirrors, for networks where YouTube itself doesn't answer.
  final mirrors = YtMirrors();

  @override
  SourceKind get kind => SourceKind.youtube;

  @override
  String get label => 'YouTube';

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async => [
    for (final c in await searchDetailed(query, limit: limit)) c.track,
  ];

  /// Search results with what helps tell the original from re-uploads:
  /// whether the channel is the artist's own ("- Topic", verified artist).
  Future<List<({Track track, bool official})>> searchDetailed(
    String query, {
    int limit = 20,
  }) async {
    try {
      final found = await _innertubeSearch(query);
      if (found.isNotEmpty) return found.take(limit).toList();
    } catch (_) {
      // Falls through to the page scraper.
    }
    final yt.VideoSearchList results;
    try {
      results = await _client.search
          .search(query)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // YouTube itself is unreachable (blocked, throttled) or its page
      // changed: ask the public mirrors instead.
      try {
        return [
          for (final v in (await mirrors.search(query)).take(limit))
            (
              track: _track(
                v.id,
                v.title,
                v.author,
                v.seconds > 0 ? Duration(seconds: v.seconds) : null,
              ),
              official: v.author.endsWith(' - Topic') || v.verified,
            ),
        ];
      } catch (_) {}
      throw StateError('YouTube search is temporarily unavailable ($e)');
    }
    return results
        .where((v) => !v.isLive)
        .take(limit)
        .map(
          (v) => (
            track: _track(v.id.value, v.title, v.author, v.duration),
            official: v.author.endsWith(' - Topic'),
          ),
        )
        .toList();
  }

  Track _track(String id, String title, String author, Duration? d) => Track(
    id: id,
    source: kind,
    title: title,
    artist: _cleanArtist(author),
    // hq720 is 16:9 without the black letterbox bars that the 4:3 "high"
    // thumbnail has; Artwork falls back if it's missing.
    artworkUrl: 'https://i.ytimg.com/vi/$id/hq720.jpg',
    duration: d,
  );

  /// YouTube's own search API, as the website calls it. Unlike scraping
  /// the results page it doesn't run into the "unusual traffic" check
  /// after a burst of searches (an import plays many new songs in a row).
  Future<List<({Track track, bool official})>> _innertubeSearch(
    String query,
  ) async {
    final visitor = await _visitor('jNQXAC9IVRw');
    final res = await _http
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
          ),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _webUa,
            'Origin': 'https://www.youtube.com',
            'X-Goog-Visitor-Id': ?visitor,
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20251110.01.00',
                'hl': 'en',
                'gl': 'US',
                'visitorData': ?visitor,
              },
            },
            'query': query,
            'params': 'EgIQAQ%3D%3D', // videos only
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw StateError('search ${res.statusCode}');
    final out = <({Track track, bool official})>[];
    void walk(Object? o) {
      if (o is Map) {
        final v = o['videoRenderer'];
        if (v is Map) {
          final r = _fromRenderer(v);
          if (r != null) out.add(r);
          return;
        }
        o.values.forEach(walk);
      } else if (o is List) {
        o.forEach(walk);
      }
    }

    walk(jsonDecode(res.body));
    return out;
  }

  ({Track track, bool official})? _fromRenderer(Map v) {
    String text(Object? o) {
      if (o is! Map) return '';
      if (o['simpleText'] is String) return o['simpleText'] as String;
      return [
        for (final r in (o['runs'] as List? ?? const []))
          (r as Map)['text'] ?? '',
      ].join();
    }

    final id = v['videoId'] as String?;
    final length = text(v['lengthText']);
    // No length: a live stream or an upcoming premiere.
    if (id == null || length.isEmpty) return null;
    var secs = 0;
    for (final part in length.split(':')) {
      secs = secs * 60 + (int.tryParse(part) ?? 0);
    }
    final author = text(v['ownerText']);
    final badges = jsonEncode(v['ownerBadges'] ?? const []);
    return (
      track: _track(id, text(v['title']), author, Duration(seconds: secs)),
      official:
          author.endsWith(' - Topic') ||
          badges.contains('VERIFIED_ARTIST') ||
          badges.contains('Official Artist Channel'),
    );
  }

  static const _webUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  /// Opus instead of AAC 128 when streaming (a setting). Downloads are
  /// always the best there is.
  bool highQuality = false;

  /// Plays a song from elsewhere when YouTube won't (see StandIn).
  Future<StreamInfo> Function(Track wanted)? standIn;

  /// YouTube didn't answer at all lately (blocked or throttled here):
  /// until then, other ways go first instead of waiting for timeouts.
  DateTime _downUntil = DateTime(0);
  bool get unreachable => DateTime.now().isBefore(_downUntil);

  @override
  Future<StreamInfo> resolveStream(Track track) =>
      _withStandIn(track, () => resolveDirect(track));

  /// A whole .m4a file for downloading (HLS is for streaming only).
  @override
  Future<StreamInfo> resolveFile(Track track) =>
      _withStandIn(track, () => resolveDirect(track, file: true));

  Future<StreamInfo> _withStandIn(
    Track track,
    Future<StreamInfo> Function() own,
  ) async {
    final other = standIn;
    if (other == null) return own();
    final wanted = songOf(track);
    if (unreachable) {
      try {
        return await other(wanted);
      } catch (_) {
        return own();
      }
    }
    try {
      return await own();
    } catch (e) {
      try {
        return await other(wanted);
      } catch (_) {
        Error.throwWithStackTrace(e, StackTrace.current);
      }
    }
  }

  /// "Artist - Song (Official Video)" by "ArtistVEVO" → Song by Artist,
  /// to look the song up elsewhere.
  static Track songOf(Track t) {
    final dash = RegExp(r'\s[-–—]\s').firstMatch(t.title);
    if (dash == null) return t;
    return Track(
      id: t.id,
      source: t.source,
      title: t.title.substring(dash.end).trim(),
      artist: t.title.substring(0, dash.start).trim(),
      duration: t.duration,
    );
  }

  /// Only YouTube's own servers and its mirrors, never a stand-in.
  Future<StreamInfo> resolveDirect(Track track, {bool file = false}) async {
    final hls = !file;
    final errors = <String>[];
    var offline = 0;
    final resolvers = [
      (String id) => _visionOs(id, hls: hls),
      _explodeFallback,
      _mirror,
    ];
    // Known to be blocked: the mirrors first.
    if (unreachable) resolvers.insert(0, resolvers.removeLast());
    for (final resolver in resolvers) {
      try {
        final info = await resolver(track.id);
        if (await _servesWholeFile(info)) {
          if (resolver != _mirror) _downUntil = DateTime(0);
          return info;
        }
        errors.add('stream rejected');
      } catch (e) {
        if (_isNetwork(e)) offline++;
        errors.add('$e'.split('\n').first);
      }
    }
    // Neither of YouTube's own ways got through to it.
    if (offline >= 2) {
      _downUntil = DateTime.now().add(const Duration(minutes: 10));
    }
    throw StateError('No playable YouTube stream for ${track.title}: $errors');
  }

  static bool _isNetwork(Object e) {
    final s = '$e';
    return e is TimeoutException ||
        e is http.ClientException ||
        s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('Connection') ||
        s.contains('timed out') ||
        s.contains('exhausted');
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
    // Each audio format says how far the track is above YouTube's
    // reference loudness.
    double? loudness;
    for (final f in (streaming['adaptiveFormats'] as List? ?? const [])) {
      final db = ((f as Map)['loudnessDb'] as num?)?.toDouble();
      if (db != null && '${f['mimeType']}'.startsWith('audio/')) {
        loudness = db;
        break;
      }
    }

    // Quick option: the audio-only HLS rendition (AAC 128 kbps). Every
    // platform player handles HLS natively, with exact duration and
    // seeking. High quality skips it for Opus.
    final hlsUrl = hls && !highQuality
        ? streaming['hlsManifestUrl'] as String?
        : null;
    if (hlsUrl != null) {
      final audio = await _hlsAudioPlaylist(hlsUrl);
      if (audio != null) {
        return StreamInfo(
          audio,
          hls: true,
          duration: duration,
          loudnessDb: loudness,
        );
      }
    }

    final formats =
        ((data['streamingData'] as Map?)?['adaptiveFormats'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .where(
              (f) =>
                  f['url'] != null &&
                  (f['mimeType'] as String? ?? '').startsWith('audio/') &&
                  // Not the dynamic-range-compressed copy, nor a dub.
                  f['isDrc'] != true &&
                  (f['audioTrack'] as Map?)?['audioIsDefault'] != false,
            )
            .toList();
    if (formats.isEmpty) throw StateError('no audio formats');
    final best = pickAudio(formats, opus: highQuality || !hls);
    return StreamInfo(
      Uri.parse(best['url'] as String),
      contentLength: int.tryParse('${best['contentLength']}'),
      mimeType: (best['mimeType'] as String).split(';').first,
      chunked: true,
      duration: duration,
      loudnessDb: loudness,
    );
  }

  /// The format to play: Opus (itag 251, ~130–160 kbps, the best YouTube
  /// gives) for high quality and files, else AAC (itag 140, 128 kbps).
  /// libmpv plays both on every platform.
  static Map<String, dynamic> pickAudio(
    List<Map<String, dynamic>> formats, {
    required bool opus,
  }) {
    bool isOpus(Map f) => '${f['mimeType']}'.contains('opus');
    final preferred = formats.where((f) => isOpus(f) == opus).toList();
    final pool = (preferred.isNotEmpty ? preferred : formats).toList()
      ..sort(
        (a, b) =>
            (b['bitrate'] as int? ?? 0).compareTo(a['bitrate'] as int? ?? 0),
      );
    return pool.first;
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

  // --- public mirrors -------------------------------------------------------

  /// The audio through a mirror, when YouTube's own servers don't answer.
  Future<StreamInfo> _mirror(String id) async {
    final a = await mirrors.audio(
      id,
      (a) => _servesWholeFile(
        StreamInfo(a.url, contentLength: a.length, chunked: true),
      ),
    );
    return StreamInfo(
      a.url,
      contentLength: a.length,
      mimeType: a.mimeType,
      chunked: a.length != null,
    );
  }

  // --- youtube_explode fallback ---------------------------------------------

  static final _fallbackClients = [
    yt.YoutubeApiClient.android,
    yt.YoutubeApiClient.ios,
    yt.YoutubeApiClient.androidVr,
  ];

  /// All fallback clients at once; the first that serves the whole file
  /// wins (one after another this took up to half a minute).
  Future<StreamInfo> _explodeFallback(String id) async {
    final done = Completer<StreamInfo>();
    var left = _fallbackClients.length;
    for (final client in _fallbackClients) {
      unawaited(
        _tryClient(id, client)
            .then((info) {
              if (info != null && !done.isCompleted) done.complete(info);
            })
            .whenComplete(() {
              if (--left == 0 && !done.isCompleted) {
                done.completeError(StateError('fallback clients exhausted'));
              }
            }),
      );
    }
    return done.future.timeout(const Duration(seconds: 20));
  }

  Future<StreamInfo?> _tryClient(String id, yt.YoutubeApiClient client) async {
    try {
      final manifest = await _client.videos.streams
          .getManifest(id, ytClients: [client])
          .timeout(const Duration(seconds: 12));
      final audio = manifest.audioOnly;
      if (audio.isEmpty) return null;
      final opus = audio.where((s) => s.audioCodec.contains('opus'));
      final mp4 = audio.where((s) => s.container == yt.StreamContainer.mp4);
      final pool = highQuality && opus.isNotEmpty
          ? opus
          : mp4.isNotEmpty
          ? mp4
          : audio;
      final s = pool.withHighestBitrate();
      final info = StreamInfo(
        s.url,
        contentLength: s.size.totalBytes,
        mimeType: s.codec.mimeType,
        chunked: true,
      );
      return await _servesWholeFile(info) ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Many clients serve only the start of a file, so probe near the end too.
  Future<bool> _servesWholeFile(StreamInfo info) async {
    if (info.hls) return true; // playlist was just fetched successfully
    final len = info.contentLength;
    final probes = [0, if (len != null && len > 2000000) len - 200000];
    final ok = await Future.wait([
      for (final start in probes)
        _http
            .get(info.url, headers: {'Range': 'bytes=$start-${start + 1023}'})
            .timeout(const Duration(seconds: 6))
            .then((r) => r.statusCode == 200 || r.statusCode == 206)
            .catchError((Object _) => false),
    ]);
    return ok.every((v) => v);
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
