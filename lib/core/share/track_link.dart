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
  ///
  /// Compact: a letter for the kind (m = a catalog or imported song,
  /// y = a YouTube video), the video id, a dot, then the title and artist
  /// (base64 of "title\nartist"). About 40 characters; the cover comes
  /// from the video, so it needn't travel.
  static String encode(Track t, {String? youtubeId}) {
    final yt = t.source == SourceKind.youtube;
    final y = yt ? t.id : (youtubeId ?? '');
    final names = base64Url
        .encode(utf8.encode('${t.displayTitle}\n${t.artist}'))
        .replaceAll('=', '');
    return '${yt ? 'y' : 'm'}$y.$names';
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
    if (!data.startsWith('eyJ')) return _decodeCompact(data);
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

  static ({Track track, String? youtubeId})? _decodeCompact(String data) {
    final m = RegExp(r'^([my])([A-Za-z0-9_-]*)\.([A-Za-z0-9_-]+)$')
        .firstMatch(data);
    if (m == null) return null;
    try {
      final b = m.group(3)!;
      final names = utf8
          .decode(base64Url.decode(b.padRight((b.length + 3) ~/ 4 * 4, '=')))
          .split('\n');
      final title = names.first.trim();
      final artist = names.length > 1 ? names[1].trim() : '';
      if (title.isEmpty) return null;
      final y = m.group(2)!.isEmpty ? null : m.group(2);
      final track = m.group(1) == 'y' && y != null
          ? Track(
              id: y,
              source: SourceKind.youtube,
              title: title,
              artist: artist,
              artworkUrl: 'https://i.ytimg.com/vi/$y/hq720.jpg',
            )
          : Track(
              id: '$artist — $title',
              source: SourceKind.match,
              title: title,
              artist: artist,
            );
      return (track: track, youtubeId: y);
    } catch (_) {
      return null;
    }
  }
}
