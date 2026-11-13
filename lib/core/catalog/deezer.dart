import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../lyrics/lyrics.dart';
import '../models/track.dart';

class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.picture,
    this.fans = 0,
  });

  final int id;
  final String name;
  final String? picture;
  final int fans;

  factory Artist.fromJson(Map j) => Artist(
    id: j['id'] as int,
    name: j['name'] as String? ?? '',
    picture:
        (j['picture_xl'] ?? j['picture_big'] ?? j['picture_medium']) as String?,
    fans: j['nb_fan'] as int? ?? 0,
  );
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.cover,
    this.year,
    this.type,
  });

  final int id;
  final String title;
  final String artist;
  final String? cover;
  final int? year;

  /// "album", "single", "ep"…
  final String? type;

  factory Album.fromJson(Map j, {String? artist}) => Album(
    id: j['id'] as int,
    title: j['title'] as String? ?? '',
    artist: artist ?? (j['artist'] as Map?)?['name'] as String? ?? '',
    cover: (j['cover_xl'] ?? j['cover_big'] ?? j['cover_medium']) as String?,
    year: int.tryParse(((j['release_date'] as String?) ?? '').split('-').first),
    type: j['record_type'] as String?,
  );
}

/// Music catalogue from Deezer's free public API (no key): artists, albums,
/// related artists, charts and artist radio.
///
/// Deezer only gives 30-second previews, so its tracks become
/// [SourceKind.match] tracks: metadata and covers from Deezer, audio matched
/// on YouTube when played.
class Catalog {
  Catalog({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _cache = <String, Object>{};

  Future<dynamic> _get(String path, {bool fresh = false}) async {
    final hit = fresh ? null : _cache[path];
    if (hit != null) return hit;
    final res = await _http
        .get(Uri.parse('https://api.deezer.com/$path'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw StateError('Deezer ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map && body['error'] != null) {
      throw StateError('Deezer: ${body['error']}');
    }
    _cache[path] = body as Object;
    return body;
  }

  static List<Map> _data(dynamic body) =>
      ((body as Map)['data'] as List? ?? const []).cast<Map>();

  /// A Deezer track as a playable Segue track.
  static Track trackFrom(Map t, {String? cover}) {
    final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
    final title = (t['title'] as String? ?? '').trim();
    final album = t['album'] as Map?;
    return Track(
      id: '$artist — $title',
      source: SourceKind.match,
      title: title,
      artist: artist,
      artworkUrl:
          cover ?? (album?['cover_xl'] ?? album?['cover_big']) as String?,
      duration: t['duration'] == null
          ? null
          : Duration(seconds: t['duration'] as int),
    );
  }

  Future<List<Artist>> searchArtists(String q, {int limit = 8}) async => [
    for (final a in _data(
      await _get('search/artist?q=${Uri.encodeQueryComponent(q)}&limit=$limit'),
    ))
      Artist.fromJson(a),
  ];

  /// The Deezer artist best matching a name (first artist of "A, B" or "A & B").
  Future<Artist?> findArtist(String name) async {
    final main = name
        .split(
          RegExp(r'\s*(,|&| feat\.? | ft\.? | x )\s*', caseSensitive: false),
        )
        .first
        .trim();
    if (main.isEmpty) return null;
    final found = await searchArtists(main, limit: 10);
    if (found.isEmpty) return null;
    // Several artists share common names: among exact matches take the one
    // most people follow.
    final exact =
        found.where((a) => a.name.toLowerCase() == main.toLowerCase()).toList()
          ..sort((a, b) => b.fans.compareTo(a.fans));
    return exact.isNotEmpty ? exact.first : found.first;
  }

  Future<Artist> artist(int id) async =>
      Artist.fromJson(await _get('artist/$id') as Map);

  Future<List<Track>> topTracks(int artistId, {int limit = 20}) async => [
    for (final t in _data(await _get('artist/$artistId/top?limit=$limit')))
      trackFrom(t),
  ];

  Future<List<Album>> albums(int artistId, String artistName) async {
    final list = [
      for (final a in _data(await _get('artist/$artistId/albums?limit=50')))
        Album.fromJson(a, artist: artistName),
    ];
    // Newest first; albums before singles when the year is the same.
    list.sort((a, b) {
      final y = (b.year ?? 0).compareTo(a.year ?? 0);
      if (y != 0) return y;
      return (a.type == 'album' ? 0 : 1).compareTo(b.type == 'album' ? 0 : 1);
    });
    return list;
  }

  Future<List<Artist>> related(int artistId) async => [
    for (final a in _data(await _get('artist/$artistId/related?limit=12')))
      Artist.fromJson(a),
  ];

  /// Deezer's radio for an artist: a fresh mix of them and similar
  /// artists on every call (not cached).
  Future<List<Track>> artistRadio(int artistId) async => [
    for (final t in _data(
      await _get('artist/$artistId/radio?limit=40', fresh: true),
    ))
      trackFrom(t),
  ];

  Future<(Album, List<Track>)> album(int id) async {
    final j = await _get('album/$id') as Map;
    final album = Album.fromJson(j);
    return (
      album,
      [
        for (final t in (j['tracks']?['data'] as List? ?? const []).cast<Map>())
          trackFrom(t, cover: album.cover),
      ],
    );
  }

  /// Tracks of the public playlists best matching [query] (mood and
  /// activity mixes: "грустные песни", "workout"…). Cached per query.
  Future<List<Track>> playlistsTracks(String query, {int playlists = 3}) async {
    final found = _data(
      await _get(
        'search/playlist?q=${Uri.encodeQueryComponent(query)}&limit=12',
      ),
    ).where((p) => (p['nb_tracks'] as int? ?? 0) >= 15).take(playlists);
    final lists = await Future.wait(
      found.map(
        (p) =>
            _get('playlist/${p['id']}/tracks?limit=100')
                .then(_data, onError: (Object _) => <Map>[]),
      ),
    );
    return [
      for (final l in lists)
        for (final t in l)
          if ((t['readable'] as bool? ?? true) && t['artist'] != null)
            trackFrom(t),
    ];
  }

  /// Top tracks: all genres (0) or a genre id from [genres].
  Future<List<Track>> chart({int genre = 0, int limit = 50}) async => [
    for (final t in _data(await _get('chart/$genre/tracks?limit=$limit')))
      trackFrom(t),
  ];

  final _bpm = <String, double?>{};

  /// Tempo of a song (beats per minute), when Deezer knows it; folded into
  /// 80…160 so half- and double-time readings compare.
  /// The album cover (1000×1000) of a song, if Deezer has the same one:
  /// for imported songs, which otherwise only have a video thumbnail.
  Future<String?> cover(String artist, String title, {Duration? length}) async {
    final found = _data(
      await _get(
        'search/track?q=${Uri.encodeQueryComponent('$artist $title')}&limit=10',
      ),
    );
    final want = (artist: artist, title: title);
    String? best;
    var bestScore = 0.0;
    for (final j in found.cast<Map>()) {
      final secs = j['duration'] as int?;
      final s = LyricsService.similarity(
        want,
        length,
        j['title'] as String? ?? '',
        (j['artist'] as Map?)?['name'] as String? ?? '',
        secs == null ? null : Duration(seconds: secs),
      );
      final album = j['album'] as Map?;
      final url = (album?['cover_xl'] ?? album?['cover_big']) as String?;
      if (s > bestScore && url != null) {
        bestScore = s;
        best = url;
      }
    }
    return best;
  }

  Future<double?> bpm(String artist, String title) async {
    final key = '${artist.toLowerCase()}|${title.toLowerCase()}';
    if (_bpm.containsKey(key)) return _bpm[key];
    double? out;
    try {
      final found = _data(
        await _get(
          'search/track?q=${Uri.encodeQueryComponent('$artist $title')}&limit=1',
        ),
      );
      if (found.isNotEmpty) {
        final t = await _get('track/${found.first['id']}') as Map;
        var b = (t['bpm'] as num?)?.toDouble() ?? 0;
        if (b > 0) {
          while (b > 160) {
            b /= 2;
          }
          while (b < 80) {
            b *= 2;
          }
          out = b;
        }
      }
    } catch (_) {
      return null; // try again later
    }
    return _bpm[key] = out;
  }

  static const genres = <int, String>{
    0: 'Все',
    132: 'Поп',
    116: 'Рэп',
    152: 'Рок',
    113: 'Танцевальная',
    106: 'Электроника',
    165: 'R&B',
    85: 'Альтернатива',
    129: 'Джаз',
  };
}

final catalogProvider = Provider<Catalog>((ref) => Catalog());

final artistByNameProvider = FutureProvider.family<Artist?, String>(
  (ref, name) => ref.read(catalogProvider).findArtist(name),
);

typedef ArtistPage = ({
  Artist artist,
  List<Track> top,
  List<Album> albums,
  List<Artist> related,
});

final artistPageProvider = FutureProvider.family<ArtistPage, int>((
  ref,
  id,
) async {
  final c = ref.read(catalogProvider);
  final artist = await c.artist(id);
  final (top, albums, related) = await (
    c.topTracks(id),
    c.albums(id, artist.name),
    c.related(id).catchError((Object _) => <Artist>[]),
  ).wait;
  return (artist: artist, top: top, albums: albums, related: related);
});

/// Every song of an artist: the popular ones first, then the releases from
/// newest to oldest (a song on a single and an album appears once).
final artistAllTracksProvider = FutureProvider.family<List<Track>, int>((
  ref,
  id,
) async {
  final c = ref.read(catalogProvider);
  final artist = await c.artist(id);
  final (top, albums) = await (
    c.topTracks(id, limit: 100),
    c.albums(id, artist.name),
  ).wait;
  final out = <Track>[];
  final seen = <String>{};
  void add(Iterable<Track> ts) {
    for (final t in ts) {
      final key = t.title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (seen.add(key)) out.add(t);
    }
  }

  add(top);
  // Six releases at a time: quick, and polite to the API.
  for (var i = 0; i < albums.length; i += 6) {
    final batch = await Future.wait([
      for (final a in albums.skip(i).take(6))
        c.album(a.id).then((r) => r.$2).catchError((Object _) => <Track>[]),
    ]);
    for (final ts in batch) {
      add(ts);
    }
  }
  return out;
});

final albumPageProvider = FutureProvider.family<(Album, List<Track>), int>(
  (ref, id) => ref.read(catalogProvider).album(id),
);

final chartProvider = FutureProvider.family<List<Track>, int>(
  (ref, genre) => ref.read(catalogProvider).chart(genre: genre),
);

final artistSearchProvider = FutureProvider.autoDispose
    .family<List<Artist>, String>(
      (ref, q) => q.trim().length < 2
          ? Future.value(const [])
          : ref.read(catalogProvider).searchArtists(q),
    );
