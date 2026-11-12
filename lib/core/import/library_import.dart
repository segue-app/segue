import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../library/library_store.dart';
import '../models/track.dart';
import 'playlist_importer.dart';

import 'package:segue/core/l10n/l10n.dart';

/// A whole library from another service: liked songs and playlists.
class ImportedLibrary {
  ImportedLibrary({
    required this.service,
    this.liked = const [],
    this.playlists = const [],
  });

  final String service;

  /// Newest first, as the services list them.
  final List<Track> liked;
  final List<ImportedPlaylist> playlists;

  int get trackCount =>
      liked.length + playlists.fold(0, (n, p) => n + p.tracks.length);
}

/// Imports everything at once.
///
/// - Yandex Music: by login (or profile link), when the profile is public —
///   "Мне нравится" and every playlist.
/// - Spotify: liked songs are private, so from export files: Exportify
///   (exportify.app, CSV per playlist incl. "Liked Songs", or their ZIP),
///   or Spotify's own "Download your data" (YourLibrary.json,
///   Playlist*.json, or the ZIP).
/// - Any CSV/TXT with "Artist - Title" lines.
class LibraryImporter {
  LibraryImporter(this._playlists, {http.Client? client})
    : _http = client ?? http.Client();

  final PlaylistImporter _playlists;
  final http.Client _http;

  // --- Yandex ---------------------------------------------------------------

  /// "ivan", "music.yandex.ru/users/ivan/…" → "ivan".
  static String? yandexLogin(String input) {
    final s = input.trim();
    final m = RegExp(r'users/([^/?#]+)').firstMatch(s);
    if (m != null) return Uri.decodeComponent(m[1]!);
    if (RegExp(r'^[\w.@+-]+$').hasMatch(s)) return s;
    return null;
  }

  Future<ImportedLibrary> yandex(
    String input, {
    void Function(String step)? progress,
    int maxPlaylists = 500,
  }) async {
    final login = yandexLogin(input);
    if (login == null) {
      throw ImportException('Введи логин Яндекса или ссылку на профиль'.tr);
    }
    progress?.call('Ищем профиль…'.tr);
    final res = await _http
        .get(
          Uri.parse(
            'https://api.music.yandex.net/users/${Uri.encodeComponent(login)}/playlists/list',
          ),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw ImportException('Профиль «{0}» не найден'.trArgs([login]));
    }
    if (res.statusCode != 200) {
      throw ImportException(
        'Профиль закрыт. В Яндекс Музыке: Настройки → Приватность → сделать профиль публичным'
            .tr,
      );
    }
    final kinds = [
      for (final p
          in ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['result']
                      as List? ??
                  const [])
              .cast<Map>())
        if (p['kind'] != null && (p['trackCount'] as int? ?? 1) > 0)
          (p['kind'] as int, p['title'] as String? ?? ''),
    ];
    Future<ImportedPlaylist?> get(int kind) async {
      try {
        return await _playlists.import(
          'https://music.yandex.ru/users/$login/playlists/$kind',
        );
      } on ImportException {
        return null;
      }
    }

    progress?.call('Загружаем «Мне нравится»…'.tr);
    final liked = await get(3);
    final rest = [
      for (final k in kinds)
        if (k.$1 != 3) k,
    ].take(maxPlaylists).toList();
    final found = List<ImportedPlaylist?>.filled(rest.length, null);
    var next = 0, done = 0;
    // Six at a time: big profiles have hundreds of playlists.
    Future<void> worker() async {
      while (next < rest.length) {
        final i = next++;
        found[i] = await get(rest[i].$1);
        progress?.call('Плейлисты: {0} из {1}'.trArgs([++done, rest.length]));
      }
    }

    await Future.wait([for (var w = 0; w < 6; w++) worker()]);
    final playlists = [
      for (final p in found)
        if (p != null && p.tracks.isNotEmpty) p,
    ];
    if ((liked?.tracks.isEmpty ?? true) && playlists.isEmpty) {
      throw ImportException(
        'В профиле нет открытых треков. Проверь, что профиль публичный'.tr,
      );
    }
    return ImportedLibrary(
      service: 'Яндекс Музыка',
      liked: liked?.tracks ?? const [],
      playlists: playlists,
    );
  }

  // --- files (Spotify exports, CSV, TXT) -------------------------------------

  /// Reads export files picked by the user; ZIPs are opened.
  ImportedLibrary files(List<({String name, Uint8List bytes})> picked) {
    final liked = <Track>[];
    final playlists = <ImportedPlaylist>[];
    void read(String name, List<int> bytes) {
      final lower = name.toLowerCase();
      final base = name.split(RegExp(r'[/\\]')).last;
      if (lower.endsWith('.zip')) {
        for (final f in ZipDecoder().decodeBytes(bytes)) {
          if (f.isFile) read(f.name, f.content as List<int>);
        }
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      if (lower.endsWith('.json')) {
        _spotifyJson(base, text, liked, playlists);
      } else if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
        final tracks = lower.endsWith('.csv') ? csvTracks(text) : _lines(text);
        if (tracks.isEmpty) return;
        final title = base
            .replaceAll(RegExp(r'\.(csv|txt)$', caseSensitive: false), '')
            .replaceAll('_', ' ');
        if (RegExp(
          r'liked|любим|мне нравится',
          caseSensitive: false,
        ).hasMatch(title)) {
          liked.addAll(tracks);
        } else {
          playlists.add(
            ImportedPlaylist(name: title, service: 'Spotify', tracks: tracks),
          );
        }
      }
    }

    for (final f in picked) {
      read(f.name, f.bytes);
    }
    if (liked.isEmpty && playlists.isEmpty) {
      throw ImportException(
        'В файлах не нашлось треков. Нужны CSV из Exportify или файлы YourLibrary.json / Playlist1.json из данных Spotify'
            .tr,
      );
    }
    return ImportedLibrary(
      service: 'Spotify',
      liked: liked,
      playlists: playlists,
    );
  }

  static void _spotifyJson(
    String name,
    String text,
    List<Track> liked,
    List<ImportedPlaylist> playlists,
  ) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      return;
    }
    if (j is! Map) return;
    // YourLibrary.json: {"tracks": [{"artist", "track", "album", "uri"}]}
    for (final t in (j['tracks'] as List? ?? const []).cast<Map>()) {
      final track = _track(t['track'], t['artist']);
      if (track != null) liked.add(track);
    }
    // Playlist1.json: {"playlists": [{"name", "items": [{"track": {...}}]}]}
    for (final p in (j['playlists'] as List? ?? const []).cast<Map>()) {
      final tracks = [
        for (final it in (p['items'] as List? ?? const []).cast<Map>())
          ?_track(
            (it['track'] as Map?)?['trackName'],
            (it['track'] as Map?)?['artistName'],
          ),
      ];
      final n = p['name'] as String? ?? 'Плейлист'.tr;
      if (tracks.isEmpty) continue;
      if (n == 'Liked Songs' || n == 'Любимые треки') {
        liked.addAll(tracks);
      } else {
        playlists.add(
          ImportedPlaylist(name: n, service: 'Spotify', tracks: tracks),
        );
      }
    }
  }

  static Track? _track(Object? title, Object? artist, {int? ms}) {
    final t = (title as String? ?? '').trim();
    final a = (artist as String? ?? '').trim();
    if (t.isEmpty || a.isEmpty) return null;
    return Track(
      id: '$a — $t',
      source: SourceKind.match,
      title: t,
      artist: a,
      duration: ms == null ? null : Duration(milliseconds: ms),
    );
  }

  /// Exportify-style CSV: columns found by name ("Track Name",
  /// "Artist Name(s)", "Duration (ms)"…). Exposed for tests.
  static List<Track> csvTracks(String text) {
    final rows = _csv(text);
    if (rows.length < 2) return const [];
    final head = [for (final h in rows.first) h.toLowerCase()];
    // Exportify also has "Artist URI(s)" (spotify:artist:…) and "Album
    // Artist Name(s)": the names of the track's own artists are wanted.
    bool idLike(String h) =>
        h.contains('uri') || h.contains(' id') || h.startsWith('id');
    int col(List<String> names, {List<String> not = const []}) =>
        head.indexWhere(
          (h) => names.any(h.contains) && !idLike(h) && !not.any(h.contains),
        );
    final ti = col(['track name', 'title', 'название']);
    var ai = col(['artist name', 'исполнитель'], not: ['album']);
    if (ai < 0) ai = col(['artist'], not: ['album']);
    final di = col(['duration']);
    if (ti < 0 || ai < 0) return const [];
    return [
      for (final r in rows.skip(1))
        if (r.length > max2(ti, ai))
          ?_track(
            r[ti],
            // "A, B" in Exportify; the first artist matches best.
            r[ai].split(RegExp(r'[,;]')).first,
            ms: di >= 0 && di < r.length ? int.tryParse(r[di]) : null,
          ),
    ];
  }

  static int max2(int a, int b) => a > b ? a : b;

  /// "Artist - Title" per line.
  static List<Track> _lines(String text) => [
    for (final line in const LineSplitter().convert(text))
      if (line.contains(' - '))
        ?_track(
          line.substring(line.indexOf(' - ') + 3),
          line.substring(0, line.indexOf(' - ')),
        ),
  ];

  /// Minimal RFC 4180 CSV: quotes, doubled quotes, commas and newlines
  /// inside quotes.
  static List<List<String>> _csv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((x) => x.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    row.add(cell.toString());
    if (row.any((x) => x.isNotEmpty)) rows.add(row);
    return rows;
  }

  /// Songs imported before the CSV fix carry "spotify:artist:…" instead of
  /// a name (and so were matched badly). Spotify's public oEmbed gives the
  /// name for such a link: puts it back. Returns the fixed tracks by key.
  static Future<Map<String, Track>> fixSpotifyArtists(
    LibraryStore library, {
    http.Client? client,
  }) async {
    final broken = library.tracksWithArtistPrefix('spotify:artist:');
    if (broken.isEmpty) return const {};
    final http_ = client ?? http.Client();
    final names = <String, String>{};
    final uris = {for (final t in broken) t.artist}.toList();
    // A few at a time: polite to Spotify, quick enough for a library.
    for (var i = 0; i < uris.length; i += 4) {
      await Future.wait([
        for (final uri in uris.skip(i).take(4))
          http_
              .get(Uri.https('open.spotify.com', '/oembed', {'url': uri}))
              .timeout(const Duration(seconds: 10))
              .then((r) {
                if (r.statusCode != 200) return;
                final name =
                    (jsonDecode(r.body) as Map)['title'] as String? ?? '';
                if (name.trim().isNotEmpty) names[uri] = name.trim();
              })
              .catchError((Object _) {}),
      ]);
    }
    final fixed = <String, Track>{};
    for (final t in broken) {
      final name = names[t.artist];
      if (name == null) continue;
      library.setArtist(t, name);
      fixed[t.key] = Track.fromJson({...t.toJson(), 'artist': name});
    }
    return fixed;
  }
}
