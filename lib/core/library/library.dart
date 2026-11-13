import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import 'library_store.dart';

/// Opened in main() and overridden there.
final libraryProvider = Provider<LibraryStore>(
  (ref) => throw UnimplementedError('libraryProvider is overridden in main()'),
);

/// Ticks on every library write; providers below re-read through it.
final _libraryVersion = StreamProvider<int>((ref) {
  var v = 0;
  return ref.watch(libraryProvider).changes.map((_) => ++v);
});

T _read<T>(Ref ref, T Function(LibraryStore s) read) {
  ref.watch(_libraryVersion);
  return read(ref.watch(libraryProvider));
}

final likedKeysProvider = Provider<Set<String>>(
  (ref) => _read(ref, (s) => s.likedKeys()),
);

final likedTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.likedTracks()),
);

final playlistsProvider = Provider<List<Playlist>>(
  (ref) => _read(ref, (s) => s.playlists()),
);

final playlistTracksProvider = Provider.family<List<Track>, String>(
  (ref, id) => _read(ref, (s) => s.playlistTracks(id)),
);

final recentlyPlayedProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.recentlyPlayed()),
);

final peersProvider = Provider<List<Peer>>(
  (ref) => _read(ref, (s) => s.peers()),
);

final downloadedKeysProvider = Provider<Set<String>>(
  (ref) => _read(ref, (s) => s.downloadedKeys()),
);

final downloadedTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.downloadedTracks()),
);

final localTracksProvider = Provider<List<Track>>(
  (ref) => _read(ref, (s) => s.localTracks()),
);

final foldersProvider = Provider<List<String>>(
  (ref) => _read(ref, (s) => [for (final f in s.folders()) f.path]),
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
  ),
);
