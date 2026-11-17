import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/track.dart';

import 'package:segue/core/l10n/l10n.dart';

class ImportedPlaylist {
  const ImportedPlaylist({
    required this.name,
    required this.service,
    required this.tracks,
  });

  final String name;

  /// "Spotify", "Яндекс Музыка", "Apple Music", "Deezer", "YouTube",
  /// "SoundCloud".
  final String service;
  final List<Track> tracks;
}

class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns a playlist link from another service into Segue tracks.
///
/// YouTube and SoundCloud tracks are playable as-is. Spotify, Yandex Music,
/// Apple Music and Deezer only give metadata; those become
/// [SourceKind.match] tracks that are matched on YouTube when played.
///
/// VK isn't here: its playlists open only to a signed-in user.
class PlaylistImporter {
  PlaylistImporter({http.Client? client, String? soundcloudClientId})
    : _http = client ?? http.Client();

  final http.Client _http;
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';

  /// Which service a link belongs to, or null if unsupported.
  static String? serviceOf(String url) {
    final u = url.toLowerCase();
    if (u.contains('spotify.com') || u.startsWith('spotify:')) return 'Spotify';
    if (u.contains('music.yandex.')) return 'Яндекс Музыка';
    if (u.contains('music.apple.com')) return 'Apple Music';
    if (u.contains('deezer.com') || u.contains('deezer.page.link')) {
      return 'Deezer';
    }
    if (u.contains('youtube.com') || u.contains('youtu.be')) return 'YouTube';
    if (u.contains('soundcloud.com')) return 'SoundCloud';
    return null;
  }

  Future<ImportedPlaylist> import(String url) async {
    final link = url.trim();
    return switch (serviceOf(link)) {
      'Spotify' => _spotify(link),
      'Яндекс Музыка' => _yandex(link),
      'Apple Music' => _apple(link),
      'Deezer' => _deezer(link),
      'YouTube' => _youtube(link),
      'SoundCloud' => _soundcloud(link),
      _ => throw ImportException(
        'Поддерживаются ссылки Spotify, Яндекс Музыки, Apple Music, Deezer, YouTube и SoundCloud'
            .tr,
      ),
    };
  }

  // --- Spotify: public embed page (up to 100 tracks, no login) -------------

  Future<ImportedPlaylist> _spotify(String url) async {
    final m = RegExp(r'(playlist|album)[/:]([a-zA-Z0-9]{22})').firstMatch(url);
    if (m == null) {
      throw ImportException(
        'Не похоже на ссылку на плейлист или альбом Spotify'.tr,
      );
    }
    final res = await _get(
      Uri.parse('https://open.spotify.com/embed/${m[1]}/${m[2]}'),
      headers: {'User-Agent': _ua, 'Referer': 'https://open.spotify.com/'},
    );
    final data = RegExp(r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>')
        .firstMatch(res.body);
    if (data == null) {
      throw ImportException('Spotify не отдал плейлист. Он публичный?'.tr);
    }
    final entity = (jsonDecode(
      data[1]!,
    ) as Map)['props']?['pageProps']?['state']?['data']?['entity'];
    final list = (entity?['trackList'] as List?) ?? const [];
    if (list.isEmpty) {
      throw ImportException('В плейлисте Spotify нет доступных треков'.tr);
    }
    final cover = RegExp(r'"(https://image-cdn[^"]+)"')
        .firstMatch(res.body)?[1];
    return ImportedPlaylist(
      name: (entity['name'] as String?) ?? 'Плейлист Spotify'.tr,
      service: 'Spotify',
      tracks: [
        for (final t in list.cast<Map>())
          if ((t['title'] as String?)?.isNotEmpty ?? false)
            _matched(
              t['title'] as String,
              (t['subtitle'] as String?) ?? '',
              t['duration'] as int?,
              // Album embeds share one cover; playlists have none per track.
              m[1] == 'album' ? cover : null,
            ),
      ],
    );
  }

  // --- Yandex Music: public API, no login for public playlists -------------

  Future<ImportedPlaylist> _yandex(String url) async {
    final user = RegExp(r'users/([^/]+)/playlists/(\d+)').firstMatch(url);
    final uuid = RegExp(r'playlists/((?:lk\.)?[0-9a-f-]{36})').firstMatch(url);
    final album = RegExp(r'album/(\d+)').firstMatch(url);
    final Uri api;
    if (user != null) {
      api = Uri.parse(
        'https://api.music.yandex.net/users/${user[1]}/playlists/${user[2]}',
      );
    } else if (uuid != null) {
      api = Uri.parse('https://api.music.yandex.net/playlist/${uuid[1]}');
    } else if (album != null) {
      api = Uri.parse(
        'https://api.music.yandex.net/albums/${album[1]}/with-tracks',
      );
    } else {
      throw ImportException(
        'Не похоже на ссылку на плейлист или альбом Яндекс Музыки'.tr,
      );
    }
    final res = await yandexGet(_http, api);
    final result = (jsonDecode(res.body) as Map)['result'] as Map?;
    if (result == null) {
      throw ImportException(
        '{0}\n\n{1}'.trArgs([
          'Яндекс Музыка не отдала плейлист. Проверь, что он открыт'.tr,
          yandexAbroad.tr,
        ]),
      );
    }

    final raw = <Map>[
      for (final t in (result['tracks'] as List?) ?? const [])
        ((t as Map)['track'] ?? t) as Map,
      // Albums come as volumes (discs) of tracks.
      for (final vol in (result['volumes'] as List?) ?? const [])
        for (final t in vol as List) t as Map,
    ];
    if (raw.isEmpty) throw ImportException('Плейлист пустой или закрыт'.tr);
    return ImportedPlaylist(
      name: (result['title'] as String?) ?? 'Плейлист Яндекс Музыки'.tr,
      service: 'Яндекс Музыка',
      tracks: [
        for (final t in raw)
          if (t['available'] != false && t['title'] != null)
            _matched(
              [
                t['title'],
                if (t['version'] != null) '(${t['version']})',
              ].join(' '),
              [
                for (final a in (t['artists'] as List?) ?? const [])
                  (a as Map)['name'],
              ].join(', '),
              t['durationMs'] as int?,
              t['coverUri'] == null
                  ? null
                  : 'https://${(t['coverUri'] as String).replaceAll('%%', '400x400')}',
            ),
      ],
    );
  }

  // --- Apple Music: the public web page carries the track list -------------

  Future<ImportedPlaylist> _apple(String url) async {
    if (!RegExp(r'/(playlist|album)/').hasMatch(url)) {
      throw ImportException(
        'Не похоже на ссылку на плейлист или альбом Apple Music'.tr,
      );
    }
    final res = await _get(Uri.parse(url), headers: {'User-Agent': _ua});
    final data = RegExp(
      r'<script type="application/json" id="serialized-server-data">([\s\S]*?)</script>',
    ).firstMatch(res.body);
    if (data == null) {
      throw ImportException('Apple Music не отдал плейлист. Он публичный?'.tr);
    }
    final rows = <Map>[];
    void walk(Object? o) {
      if (o is Map) {
        if ('${o['id']}'.startsWith('track-lockup') && o['title'] != null) {
          rows.add(o);
          return;
        }
        o.values.forEach(walk);
      } else if (o is List) {
        o.forEach(walk);
      }
    }

    walk(jsonDecode(data[1]!));
    if (rows.isEmpty) {
      throw ImportException('В плейлисте Apple Music нет доступных треков'.tr);
    }
    // The name, without " on Apple Music", is in the page's structured data.
    String? name;
    for (final m in RegExp(
      r'<script[^>]*application/ld\+json[^>]*>([\s\S]*?)</script>',
    ).allMatches(res.body)) {
      try {
        name ??= (jsonDecode(m[1]!) as Map)['name'] as String?;
      } catch (_) {}
    }
    return ImportedPlaylist(
      name: name ?? 'Плейлист Apple Music'.tr,
      service: 'Apple Music',
      tracks: [
        for (final t in rows)
          _matched(
            t['title'] as String,
            (t['artistName'] as String?) ?? '',
            (t['duration'] as num?)?.toInt(),
            _appleCover(t['artwork']),
          ),
      ],
    );
  }

  static String? _appleCover(Object? artwork) {
    if (artwork is! Map) return null;
    final url = (artwork['dictionary'] as Map?)?['url'];
    if (url is! String) return null;
    return url
        .replaceAll('{w}', '400')
        .replaceAll('{h}', '400')
        .replaceAll('{c}', 'bb')
        .replaceAll('{f}', 'jpg');
  }

  // --- Deezer: open API ----------------------------------------------------

  Future<ImportedPlaylist> _deezer(String url) async {
    var link = url;
    // Share links (link.deezer.com/s/…, deezer.page.link/…) redirect to
    // the real page.
    if (!RegExp(r'deezer\.com/(?:[a-z]{2}/)?(?:playlist|album)/')
        .hasMatch(link)) {
      link = await _resolve(link);
    }
    final m = RegExp(r'deezer\.com/(?:[a-z]{2}/)?(playlist|album)/(\d+)')
        .firstMatch(link);
    if (m == null) {
      throw ImportException(
        'Не похоже на ссылку на плейлист или альбом Deezer'.tr,
      );
    }
    final kind = m[1]!, id = m[2]!;
    final head = jsonDecode(
      (await _get(Uri.parse('https://api.deezer.com/$kind/$id'))).body,
    ) as Map;
    if (head['error'] != null) {
      throw ImportException('Плейлист не найден. Проверь ссылку'.tr);
    }
    final albumCover = kind == 'album' ? head['cover_medium'] as String? : null;
    final raw = <Map>[];
    String? next = 'https://api.deezer.com/$kind/$id/tracks?limit=100';
    while (next != null && raw.length < 2000) {
      final page = jsonDecode((await _get(Uri.parse(next))).body) as Map;
      raw.addAll(((page['data'] as List?) ?? const []).cast<Map>());
      next = page['next'] as String?;
    }
    if (raw.isEmpty) throw ImportException('Плейлист пустой или закрыт'.tr);
    return ImportedPlaylist(
      name: (head['title'] as String?) ?? 'Плейлист Deezer'.tr,
      service: 'Deezer',
      tracks: [
        for (final t in raw)
          if (t['title'] != null)
            _matched(
              t['title'] as String,
              ((t['artist'] as Map?)?['name'] as String?) ?? '',
              t['duration'] == null
                  ? null
                  : (t['duration'] as num).toInt() * 1000,
              albumCover ?? (t['album'] as Map?)?['cover_medium'] as String?,
            ),
      ],
    );
  }

  /// Where a short link leads, following a few redirects.
  Future<String> _resolve(String url) async {
    var uri = Uri.parse(url);
    for (var i = 0; i < 5; i++) {
      final req = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['User-Agent'] = _ua;
      final res = await _http.send(req).timeout(const Duration(seconds: 20));
      await res.stream.drain<void>();
      final to = res.headers['location'];
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        if (to == null) break;
        uri = uri.resolve(to);
        continue;
      }
      break;
    }
    return uri.toString();
  }

  // --- YouTube: playable directly -----------------------------------------

  Future<ImportedPlaylist> _youtube(String url) async {
    final id = yt.PlaylistId.parsePlaylistId(url);
    if (id == null) {
      throw ImportException(
        'В ссылке нет плейлиста YouTube (параметр list=)'.tr,
      );
    }
    final client = yt.YoutubeExplode();
    try {
      final playlist = await client.playlists.get(id);
      final videos = await client.playlists.getVideos(id).take(300).toList();
      return ImportedPlaylist(
        name: playlist.title,
        service: 'YouTube',
        tracks: [
          for (final v in videos)
            Track(
              id: v.id.value,
              source: SourceKind.youtube,
              title: v.title,
              artist: v.author.endsWith(' - Topic')
                  ? v.author.substring(0, v.author.length - 8)
                  : v.author,
              artworkUrl: 'https://i.ytimg.com/vi/${v.id.value}/hq720.jpg',
              duration: v.duration,
            ),
        ],
      );
    } finally {
      client.close();
    }
  }

  // --- SoundCloud sets: playable directly ----------------------------------

  /// Set by the app with the client id SoundCloudSource already found.
  Future<String> Function()? soundcloudClientId;

  Future<ImportedPlaylist> _soundcloud(String url) async {
    final getId = soundcloudClientId;
    if (getId == null) throw ImportException('SoundCloud недоступен'.tr);
    final id = await getId();
    final res = await _get(
      Uri.https('api-v2.soundcloud.com', '/resolve', {
        'url': url,
        'client_id': id,
      }),
    );
    final set = jsonDecode(res.body) as Map;
    if (set['kind'] != 'playlist') {
      throw ImportException('Это не плейлист SoundCloud'.tr);
    }
    var items = ((set['tracks'] as List?) ?? const []).cast<Map>();
    // Long sets only include full data for the first few tracks.
    final missing = [
      for (final t in items)
        if (t['title'] == null) t['id'],
    ];
    if (missing.isNotEmpty) {
      final full = <Map>[];
      for (var i = 0; i < missing.length; i += 50) {
        final r = await _get(
          Uri.https('api-v2.soundcloud.com', '/tracks', {
            'ids': missing.skip(i).take(50).join(','),
            'client_id': id,
          }),
        );
        full.addAll((jsonDecode(r.body) as List).cast<Map>());
      }
      final byId = {for (final t in full) t['id']: t};
      items = [
        for (final t in items) t['title'] == null ? (byId[t['id']] ?? t) : t,
      ];
    }
    return ImportedPlaylist(
      name: (set['title'] as String?) ?? 'Плейлист SoundCloud'.tr,
      service: 'SoundCloud',
      tracks: [
        for (final t in items)
          if (t['title'] != null && t['policy'] == 'ALLOW')
            Track(
              id: '${t['id']}',
              source: SourceKind.soundcloud,
              title: t['title'] as String,
              artist: ((t['user'] as Map?)?['username'] as String?) ?? '',
              artworkUrl: (t['artwork_url'] as String?)?.replaceAll(
                '-large.',
                '-t500x500.',
              ),
              duration: t['duration'] == null
                  ? null
                  : Duration(milliseconds: t['duration'] as int),
            ),
      ],
    );
  }

  // --- helpers -------------------------------------------------------------

  static Track _matched(
    String title,
    String artist,
    int? durationMs,
    String? cover,
  ) => Track(
    id: '$artist — $title',
    source: SourceKind.match,
    title: title.trim(),
    artist: artist.trim(),
    artworkUrl: cover,
    duration: durationMs == null ? null : Duration(milliseconds: durationMs),
  );

  /// Outside Russia and Belarus Yandex Music often won't answer without a
  /// Plus subscription: the request goes from the user's own address.
  static const yandexAbroad =
      'Если ты не в России или Беларуси, Яндекс Музыка может не пускать. Включи VPN с сервером в России или Беларуси и попробуй снова';

  /// A Yandex Music API call, its failures explained (closed playlist or
  /// blocked from abroad).
  static Future<http.Response> yandexGet(http.Client client, Uri uri) async {
    final http.Response res;
    try {
      res = await client.get(uri).timeout(const Duration(seconds: 20));
    } on ImportException {
      rethrow;
    } catch (_) {
      throw ImportException(
        '{0}\n\n{1}'.trArgs(['Яндекс Музыка не отвечает'.tr, yandexAbroad.tr]),
      );
    }
    if (res.statusCode == 404) {
      throw ImportException('Плейлист не найден. Проверь ссылку'.tr);
    }
    if (res.statusCode != 200) {
      throw ImportException(
        '{0}\n\n{1}'.trArgs([
          'Яндекс Музыка не пустила (ошибка {0}). Плейлист должен быть открытым'
              .trArgs([res.statusCode]),
          yandexAbroad.tr,
        ]),
      );
    }
    return res;
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    final res = await _http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw ImportException('Плейлист не найден. Проверь ссылку'.tr);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw ImportException(
        'Плейлист закрытый. Сделай его публичным и попробуй снова'.tr,
      );
    }
    if (res.statusCode != 200) {
      throw ImportException(
        'Сервис ответил ошибкой {0}'.trArgs([res.statusCode]),
      );
    }
    return res;
  }
}
