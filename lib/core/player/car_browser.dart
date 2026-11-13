import 'package:audio_service/audio_service.dart';

import '../catalog/wave.dart';
import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../models/track.dart';

/// What Android Auto (and other media browsers: Wear, Assistant) shows:
/// My wave, liked songs, playlists and recent plays. Picking a song plays
/// its whole list from it; "play … on Segue" searches.
class CarBrowser {
  CarBrowser({
    required this.library,
    required this.playList,
    required this.startWave,
    required this.search,
  });

  final LibraryStore library;
  final Future<void> Function(List<Track> list, int start, {String? context})
  playList;

  /// Starts My wave with the saved wave settings.
  final Future<void> Function() startWave;
  final Future<List<Track>> Function(String query) search;

  static const _wave = 'wave';
  static const _liked = 'liked';
  static const _playlists = 'playlists';
  static const _recent = 'history';
  static const _found = 'found';

  /// Lists stay short: a car screen isn't for scrolling.
  static const _max = 150;

  /// The last search's songs, so a pick plays them as a list.
  List<Track> _lastFound = const [];

  Future<List<MediaItem>> children(String parent) async {
    if (parent == AudioService.browsableRootId) {
      return [
        MediaItem(
          id: _wave,
          title: Wave.myWaveTitle.tr,
          playable: true,
          extras: const {'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 2},
        ),
        _folder(_liked, 'Любимые'.tr),
        _folder(_playlists, 'Плейлисты'.tr),
        _folder(_recent, 'Недавние'.tr),
      ];
    }
    if (parent == AudioService.recentRootId) {
      // "Resume" on the car's home: the latest song.
      final t = library.recentlyPlayed(limit: 1);
      return [for (final x in t) _song('$_recent|${x.key}', x)];
    }
    if (parent == _liked) {
      return [
        for (final t in library.likedTracks().take(_max))
          _song('$_liked|${t.key}', t),
      ];
    }
    if (parent == _recent) {
      return [
        for (final t in library.recentlyPlayed(limit: _max))
          _song('$_recent|${t.key}', t),
      ];
    }
    if (parent == _playlists) {
      return [
        for (final p in library.playlists()) _folder('pl|${p.id}', p.name),
      ];
    }
    if (parent.startsWith('pl|')) {
      final id = parent.substring(3);
      return [
        for (final t in library.playlistTracks(id).take(_max))
          _song('pl|$id|${t.key}', t),
      ];
    }
    return const [];
  }

  /// Plays what was picked: the wave, or a song with the rest of its list.
  Future<void> play(String mediaId) async {
    if (mediaId == _wave) return _startWave();
    final bar = mediaId.indexOf('|');
    if (bar < 0) return;
    final kind = mediaId.substring(0, bar);
    var rest = mediaId.substring(bar + 1);
    List<Track> list;
    String? context;
    switch (kind) {
      case _liked:
        list = library.likedTracks();
        context = 'liked';
      case _recent:
        list = library.recentlyPlayed(limit: _max);
      case _found:
        list = _lastFound;
      case 'pl':
        final i = rest.indexOf('|');
        if (i < 0) return;
        final id = rest.substring(0, i);
        rest = rest.substring(i + 1);
        list = library.playlistTracks(id);
        context = 'playlist:$id';
      default:
        return;
    }
    final at = list.indexWhere((t) => t.key == rest);
    if (at < 0) return;
    await playList(list, at, context: context);
  }

  /// Search from the car's search button.
  Future<List<MediaItem>> find(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final mine = _inLibrary(q);
    final more = await search(q).catchError((Object _) => <Track>[]);
    final seen = <String>{};
    _lastFound = [
      for (final t in [...mine, ...more])
        if (seen.add(t.key)) t,
    ].take(40).toList();
    return [for (final t in _lastFound) _song('$_found|${t.key}', t)];
  }

  /// "Play … on Segue" by voice; nothing said means My wave.
  Future<void> playSearch(String query) async {
    if (query.trim().isEmpty) return _startWave();
    final found = await find(query);
    if (found.isEmpty) return;
    await playList(_lastFound, 0);
  }

  // Offline or an empty catalog: the car just stays where it was.
  Future<void> _startWave() => startWave().catchError((Object _) {});

  List<Track> _inLibrary(String q) {
    final words = q.toLowerCase().split(RegExp(r'\s+'));
    bool hit(Track t) {
      final s = '${t.title} ${t.artist}'.toLowerCase();
      return words.every(s.contains);
    }

    return [
      ...library.likedTracks().where(hit),
      ...library.recentlyPlayed(limit: 300).where(hit),
    ];
  }

  MediaItem _folder(String id, String title) =>
      MediaItem(id: id, title: title, playable: false);

  MediaItem _song(String id, Track t) => MediaItem(
    id: id,
    title: t.displayTitle,
    artist: t.artist,
    duration: t.duration,
    playable: true,
    artUri: t.artworkUrl == null || t.artworkUrl!.startsWith('/')
        ? null
        : Uri.tryParse(t.artworkUrl!),
  );
}
