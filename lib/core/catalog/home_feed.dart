import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';
import '../library/library_store.dart';
import '../models/track.dart';
import 'deezer.dart';
import 'taste.dart';

/// An artist you listen to, for "Твои исполнители".
class FavArtist {
  const FavArtist(this.name, this.latest, this.deezer);

  final String name;

  /// Your newest song of theirs (its cover when Deezer has no photo).
  final Track latest;

  /// Deezer's page of them; null for artists it doesn't know.
  final Artist? deezer;

  String? get picture {
    final p = deezer?.picture;
    // Deezer's blank silhouette for artists without a photo.
    if (p != null && !p.contains('/artist//')) return p;
    return latest.artworkUrl;
  }
}

final _first = RegExp(
  r'\s*(,|&| feat\.? | ft\.? | x | and | и )\s*',
  caseSensitive: false,
);

/// The artists you listen to most lately, best first.
final favouriteArtistsProvider = FutureProvider<List<FavArtist>>((ref) async {
  final library = ref.read(libraryProvider);
  final catalog = ref.read(catalogProvider);
  final taste = ref.read(tasteProvider);
  final by = <String, ({String name, double score, Track latest})>{};
  for (final a in library.topArtists(days: 90, limit: 60)) {
    final name = a.artist.split(_first).first.trim();
    final key = name.toLowerCase();
    if (name.isEmpty || taste.artist(name) < 0) continue;
    final had = by[key];
    by[key] = (
      name: had?.name ?? name,
      score: (had?.score ?? 0) + a.score,
      latest: had?.latest ?? a.latest,
    );
  }
  final top = (by.values.toList()..sort((a, b) => b.score.compareTo(a.score)))
      .where((a) => a.score >= 2)
      .take(14)
      .toList();
  final found = await Future.wait(
    top.map((a) => _deezerArtist(library, catalog, a.name)),
  );
  return [
    for (var i = 0; i < top.length; i++)
      FavArtist(top[i].name, top[i].latest, found[i]),
  ];
});

/// Deezer's artist of that exact name, remembered for a week (also that
/// there is none).
Future<Artist?> _deezerArtist(
  LibraryStore library,
  Catalog catalog,
  String name,
) async {
  final key = name.toLowerCase();
  final now = DateTime.now().millisecondsSinceEpoch;
  final hit = library.kvGet('artist_dz', key);
  if (hit is Map && now - (hit['at'] as int? ?? 0) < 7 * 86400000) {
    final id = hit['id'];
    return id is int
        ? Artist(
            id: id,
            name: hit['name'] as String? ?? name,
            picture: hit['picture'] as String?,
          )
        : null;
  }
  try {
    final a = await catalog.findArtist(name, strict: true);
    library.kvPut('artist_dz', key, {
      'at': now,
      if (a != null) ...{'id': a.id, 'name': a.name, 'picture': a.picture},
    }, keep: 500);
    return a;
  } catch (_) {
    return null;
  }
}

/// New albums and singles of your artists, from the last two months,
/// newest first.
final newReleasesProvider = FutureProvider<List<Album>>((ref) async {
  final artists = await ref.watch(favouriteArtistsProvider.future);
  final catalog = ref.read(catalogProvider);
  final since = DateTime.now().subtract(const Duration(days: 60));
  final lists = await Future.wait([
    for (final a in artists)
      if (a.deezer != null)
        catalog
            .albums(a.deezer!.id, a.deezer!.name)
            .catchError((Object _) => <Album>[]),
  ]);
  final seen = <String>{};
  final out = [
    for (final l in lists)
      for (final al in l)
        if (al.released != null &&
            al.released!.isAfter(since) &&
            seen.add('${al.artist}|${al.title}'.toLowerCase()))
          al,
  ]..sort((a, b) => b.released!.compareTo(a.released!));
  return out.take(20).toList();
});
