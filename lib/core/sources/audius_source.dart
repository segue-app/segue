import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'music_source.dart';

/// Audius: an open music platform (lots of phonk, hip-hop, electronic and
/// remixes) with a public API that needs no account and no key, only an
/// app name. Streams are plain MP3 files, so they seek and download like
/// any file.
class AudiusSource implements MusicSource, FileSource {
  AudiusSource({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _api = 'https://api.audius.co/v1';

  /// Audius asks every app to name itself.
  static const _app = 'segue';

  static const _timeout = Duration(seconds: 15);

  @override
  SourceKind get kind => SourceKind.audius;

  @override
  String get label => 'Audius';

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final data = await _getJson(
      Uri.parse('$_api/tracks/search')
          .replace(queryParameters: {'query': query, 'app_name': _app}),
    );
    return [
      for (final t in (data['data'] as List? ?? const []).cast<Map>())
        if (t['is_streamable'] != false &&
            t['is_delete'] != true &&
            t['title'] != null)
          trackFrom(t),
    ].take(limit).toList();
  }

  /// An Audius track (from the API) as a Segue track.
  static Track trackFrom(Map t) {
    final art = t['artwork'] as Map?;
    final user = t['user'] as Map?;
    return Track(
      id: '${t['id']}',
      source: SourceKind.audius,
      title: (t['title'] as String).trim(),
      artist: ((user?['name'] ?? user?['handle']) as String? ?? '').trim(),
      artworkUrl:
          (art?['480x480'] ?? art?['1000x1000'] ?? art?['150x150']) as String?,
      duration: t['duration'] == null
          ? null
          : Duration(seconds: (t['duration'] as num).round()),
    );
  }

  /// The file's address (it holds for a couple of hours).
  @override
  Future<StreamInfo> resolveStream(Track track) async {
    final data = await _getJson(
      Uri.parse('$_api/tracks/${track.id}/stream')
          .replace(queryParameters: {'app_name': _app, 'no_redirect': 'true'}),
    );
    final url = data['data'];
    if (url is! String || url.isEmpty) {
      throw StateError('Audius: нет записи для ${track.title}');
    }
    return StreamInfo(
      Uri.parse(url),
      mimeType: 'audio/mpeg',
      duration: track.duration,
    );
  }

  /// The same MP3 file is the download.
  @override
  Future<StreamInfo> resolveFile(Track track) => resolveStream(track);

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode == 404) {
      throw StateError('Audius: трек удалён');
    }
    if (res.statusCode != 200) {
      throw StateError('Audius ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }
}
