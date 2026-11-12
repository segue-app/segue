import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'music_source.dart';

/// SoundCloud search and streams through the public web API (api-v2).
///
/// The web client id is not published; it is read from SoundCloud's own
/// JavaScript bundles, the same way the website gets it, and cached.
class SoundCloudSource implements MusicSource, FileSource {
  SoundCloudSource({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  String? _clientId;

  static const _api = 'https://api-v2.soundcloud.com';

  /// A stalled request must not freeze search or playback forever.
  static const _timeout = Duration(seconds: 15);

  @override
  SourceKind get kind => SourceKind.soundcloud;

  @override
  String get label => 'SoundCloud';

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    // Label uploads are often 30-second previews (policy SNIP, the full
    // track is only for SoundCloud Go+). We drop those, so page through
    // results until we have enough full tracks.
    final out = <Track>[];
    Uri? page = Uri.parse('$_api/search/tracks')
        .replace(queryParameters: {'q': query, 'limit': '50'});
    for (var i = 0; i < 3 && page != null && out.length < limit; i++) {
      final data = await _getJson(page);
      final items = (data['collection'] as List).cast<Map<String, dynamic>>();
      out.addAll(
        items
            .where((t) => t['streamable'] != false && t['policy'] == 'ALLOW')
            .map(_toTrack),
      );
      final next = data['next_href'] as String?;
      page = next == null ? null : Uri.parse(next);
    }
    return out.take(limit).toList();
  }

  /// Same as streaming: progressive MP3 when available, HLS otherwise (the
  /// downloader joins HLS segments into one file).
  @override
  Future<StreamInfo> resolveFile(Track track) => resolveStream(track);

  @override
  Future<StreamInfo> resolveStream(Track track) async {
    final data = await _getJson(Uri.parse('$_api/tracks/${track.id}'));
    final transcodings =
        ((data['media'] as Map?)?['transcodings'] as List? ?? [])
            .cast<Map<String, dynamic>>();
    // Progressive MP3 is a single file, which every player handles; fall
    // back to HLS when a track has no progressive version.
    Map<String, dynamic>? pick(String protocol) {
      for (final t in transcodings) {
        if ((t['format'] as Map)['protocol'] == protocol) return t;
      }
      return null;
    }

    final chosen = pick('progressive') ?? pick('hls');
    if (chosen == null) throw StateError('No stream for ${track.title}');
    final resolved = await _getJson(Uri.parse(chosen['url'] as String));
    final isHls = (chosen['format'] as Map)['protocol'] == 'hls';
    return StreamInfo(
      Uri.parse(resolved['url'] as String),
      hls: isHls,
      duration: track.duration,
    );
  }

  Track _toTrack(Map<String, dynamic> t) {
    final user = t['user'] as Map<String, dynamic>?;
    final art = (t['artwork_url'] ?? user?['avatar_url']) as String?;
    return Track(
      id: '${t['id']}',
      source: kind,
      title: t['title'] as String? ?? 'Untitled',
      artist: user?['username'] as String? ?? '',
      // Default artwork is 100x100; the t500x500 variant always exists.
      artworkUrl: art?.replaceAll('-large.', '-t500x500.'),
      duration: t['duration'] == null
          ? null
          : Duration(milliseconds: t['duration'] as int),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {bool retried = false}) async {
    final id = await _getClientId();
    final withId = uri.replace(
      queryParameters: {...uri.queryParameters, 'client_id': id},
    );
    final res = await _http.get(withId).timeout(_timeout);
    // The client id rotates; refresh it once on auth errors.
    if ((res.statusCode == 401 || res.statusCode == 403) && !retried) {
      _clientId = null;
      return _getJson(uri, retried: true);
    }
    if (res.statusCode != 200) {
      throw http.ClientException('SoundCloud ${res.statusCode}', withId);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Web client id (found and cached); also used by the playlist importer.
  Future<String> clientId() => _getClientId();

  Future<String> _getClientId() async {
    if (_clientId != null) return _clientId!;
    final page = await _http
        .get(Uri.parse('https://soundcloud.com/'))
        .timeout(_timeout);
    final scripts = RegExp(
      r'<script crossorigin src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"',
    ).allMatches(page.body).map((m) => m.group(1)!).toList().reversed; // the id usually lives in one of the last bundles
    final idPattern = RegExp(r'client_id\s*[:=]\s*"([a-zA-Z0-9]{32})"');
    // All bundles at once (one slow file used to hold up the rest); the
    // first that contains the id wins.
    final found = Completer<String>();
    var left = 0;
    for (final src in scripts) {
      left++;
      unawaited(
        _http
            .get(Uri.parse(src))
            .timeout(_timeout)
            .then((js) {
              final m = idPattern.firstMatch(js.body);
              if (m != null && !found.isCompleted) found.complete(m.group(1)!);
            })
            .catchError((Object _) {})
            .whenComplete(() {
              if (--left == 0 && !found.isCompleted) {
                found.completeError(
                  StateError('Could not find SoundCloud client id'),
                );
              }
            }),
      );
    }
    if (left == 0) throw StateError('Could not find SoundCloud client id');
    return _clientId = await found.future;
  }
}
