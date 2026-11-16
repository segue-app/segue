import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/deezer.dart';
import '../models/track.dart';
import 'library_store.dart';

/// Opened in main() and overridden there.
final libraryProvider = Provider<LibraryStore>(
  (ref) => throw UnimplementedError('libraryProvider is overridden in main()'),
);

/// Ticks on the library writes of one area; providers below re-read
/// through it. Before, every write (a play recorded, a peer saved after a
/// sync, a cover found) re-ran every query and decoded every liked song.
final _version = StreamProvider.family<int, _Area>((ref, area) {
  var v = 0;
  return ref
      .watch(libraryProvider)
      .changeKinds
      .where(area.kinds.contains)
      .map((_) => ++v);
});

enum _Area {
  /// Likes, playlists, saved albums and the songs' own data.
  music({LibChange.edit, LibChange.synced, LibChange.artwork}),

  /// What was played (and the smart lists made from it and from likes).
  plays({
    LibChange.history,
    LibChange.edit,
    LibChange.synced,
    LibChange.artwork,
  }),
  downloads({LibChange.downloads, LibChange.artwork}),
  local({LibChange.local}),
  peers({LibChange.peers});

  const _Area(this.kinds);
  final Set<LibChange> kinds;
}

T _read<T>(
  Ref ref,
  T Function(LibraryStore s) read, [
  _Area area = _Area.music,
]) {
  ref.watch(_version(area));
  return read(ref.watch(libraryProvider));
}

final likedKeysProvider = Provider<Set<String>>(
  (ref) => _read(ref, (s) => s.likedKeys()),
);

final likedTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.likedTracks()),
);

/// Albums added to the library, newest first.
final savedAlbumsProvider = Provider<List<Album>>(
  (ref) => _read(
    ref,
    (s) => [for (final j in s.saved('album')) ?Album.fromSaved(j)],
  ),
);

final playlistsProvider = Provider<List<Playlist>>(
  (ref) => _read(ref, (s) => s.playlists()),
);

final playlistTracksProvider = Provider.family<List<Track>, String>(
  (ref, id) => _read(ref, (s) => s.playlistTracks(id)),
);

final recentlyPlayedProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.recentlyPlayed(), _Area.plays),
);

final listeningHistoryProvider = Provider<List<(Track, DateTime)>>(
  (ref) => _read(ref, (s) => s.listeningHistory(), _Area.plays),
);

final peersProvider = Provider<List<Peer>>(
  (ref) => _read(ref, (s) => s.peers(), _Area.peers),
);

final downloadedKeysProvider = Provider<Set<String>>(
  (ref) => _read(ref, (s) => s.downloadedKeys(), _Area.downloads),
);

final downloadedTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.downloadedTracks(), _Area.downloads),
);

final localTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.localTracks(), _Area.local),
);

final foldersProvider = Provider<List<String>>(
  (ref) =>
      _read(ref, (s) => [for (final f in s.folders()) f.path], _Area.local),
);

/// Smart playlists, put together from listening (see LibraryStore).
enum SmartList { onRepeat, forgotten, newLikes }

final smartTracksProvider = Provider.family<List<Track>, SmartList>(
  (ref, kind) => _read(
    ref,
    (s) => switch (kind) {
      SmartList.onRepeat => s.smartOnRepeat(),
      SmartList.forgotten => s.smartForgotten(),
      SmartList.newLikes => s.smartNewLikes(),
    },
    _Area.plays,
  ),
);
