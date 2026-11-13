import 'dart:convert';

import '../models/track.dart';

/// Links to a song that anyone can open: in Segue if they have it, on
/// YouTube otherwise (the web page decides, see docs/t/index.html).
///
/// Everything needed is in the link itself (#…), so there's no server.
class TrackLink {
  TrackLink._();

  static const web = 'https://segue-app.github.io/segue/t/';

  /// [youtubeId] is the exact video this device plays the song from.
  static String encode(Track t, {String? youtubeId}) {
    final j = <String, Object?>{
      's': t.source == SourceKind.youtube ? 'yt' : 'm',
      'id': t.id,
      't': t.displayTitle,
      'a': t.artist,
      'y': ?(t.source == SourceKind.youtube ? t.id : youtubeId),
      'c': ?t.artworkUrl,
      'd': ?t.duration?.inSeconds,
    };
    return base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
  }

  static String webLink(Track t, {String? youtubeId}) =>
      '$web#${encode(t, youtubeId: youtubeId)}';

  /// The song in a link (segue://track?d=…, or the web link), and the
  /// YouTube version it played from, if known.
  static ({Track track, String? youtubeId})? decode(Uri uri) {
    final data =
        uri.queryParameters['d'] ??
        (uri.fragment.isNotEmpty ? uri.fragment : null);
    if (data == null) return null;
    try {
      final padded = data.padRight((data.length + 3) ~/ 4 * 4, '=');
      final j = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map;
      final title = j['t'] as String? ?? '';
      final artist = j['a'] as String? ?? '';
      if (title.isEmpty) return null;
      final y = j['y'] as String?;
      final d = j['d'] as int?;
      final duration = d == null ? null : Duration(seconds: d);
      final track = j['s'] == 'yt' && y != null
          ? Track(
              id: y,
              source: SourceKind.youtube,
              title: title,
              artist: artist,
              artworkUrl: j['c'] as String?,
              duration: duration,
            )
          : Track(
              id: j['id'] as String? ?? '$artist — $title',
              source: SourceKind.match,
              title: title,
              artist: artist,
              artworkUrl: j['c'] as String?,
              duration: duration,
            );
      return (track: track, youtubeId: y);
    } catch (_) {
      return null;
    }
  }
}
