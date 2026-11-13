import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../models/track.dart';

import 'package:segue/core/l10n/l10n.dart';

/// A user playlist (tracks are loaded separately).
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.count,
    this.coverUrl,
  });

  final String id;
  final String name;
  final int count;

  /// Artwork of the first track, used as the playlist cover.
  final String? coverUrl;
}

/// A paired device.
class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.token,
    this.sentSeq = 0,
    this.recvSeq = 0,
    this.host,
    this.port,
  });

  final String id;
  final String name;
  final String platform;

  /// Shared secret from pairing; both sides send it with every request.
  final String token;

  /// Our change number the peer has already received.
  final int sentSeq;

  /// The peer's change number we have already applied.
  final int recvSeq;

  /// Last known address on the local network.
  final String? host;
  final int? port;

  Peer copyWith({
    int? sentSeq,
    int? recvSeq,
    String? host,
    int? port,
    String? name,
  }) => Peer(
    id: id,
    name: name ?? this.name,
    platform: platform,
    token: token,
    sentSeq: sentSeq ?? this.sentSeq,
    recvSeq: recvSeq ?? this.recvSeq,
    host: host ?? this.host,
    port: port ?? this.port,
  );
}

/// Local library: likes, playlists and listening history, in SQLite.
///
/// Built to be synced between devices later: rows carry `updated_at`
/// (ms since epoch) and are soft-deleted (`deleted = 1`) instead of
/// removed, so a sync can tell "deleted on the phone" from "never existed".
class LibraryStore {
  LibraryStore._(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();
  static const _uuid = Uuid();

  /// Fires after every write; the UI re-reads what it shows.
  Stream<void> get changes => _changes.stream;

  static Future<LibraryStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return LibraryStore._(
      sqlite3.open('${dir.path}${Platform.pathSeparator}library.db'),
    ).._migrate();
  }

  /// A store in the given file (tools and tests).
  factory LibraryStore.at(String path) =>
      LibraryStore._(sqlite3.open(path)).._migrate();

  /// In-memory store for tests.
  factory LibraryStore.memory() =>
      LibraryStore._(sqlite3.openInMemory()).._migrate();

  void _migrate() {
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
        key TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS likes (
        track_key TEXT PRIMARY KEY,
        liked_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS playlist_items (
        playlist_id TEXT NOT NULL,
        track_key TEXT NOT NULL,
        position REAL NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_key)
      );
      CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_key TEXT NOT NULL,
        played_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS history_played ON history (played_at DESC);
      CREATE TABLE IF NOT EXISTS downloads (
        track_key TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        size INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS local_files (
        path TEXT PRIMARY KEY,
        folder TEXT NOT NULL,
        json TEXT NOT NULL,
        modified INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS folders (
        path TEXT PRIMARY KEY,
        bookmark TEXT
      );
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS peers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        platform TEXT NOT NULL DEFAULT '',
        token TEXT NOT NULL,
        sent_seq INTEGER NOT NULL DEFAULT 0,
        recv_seq INTEGER NOT NULL DEFAULT 0,
        host TEXT,
        port INTEGER
      );
    ''');
    // v1: every synced row gets `seq`, a local change counter. Sync sends
    // "everything with seq > what the peer already has". (updated_at alone
    // can't do this: rows arriving from a third device keep old timestamps.)
    for (final table in [
      'tracks',
      'likes',
      'playlists',
      'playlist_items',
      'history',
    ]) {
      final cols = _db
          .select('PRAGMA table_info($table)')
          .map((r) => r['name']);
      if (!cols.contains('seq')) {
        _db.execute(
          'ALTER TABLE $table ADD COLUMN seq INTEGER NOT NULL DEFAULT 0',
        );
      }
      _db.execute('CREATE INDEX IF NOT EXISTS ${table}_seq ON $table (seq)');
    }
    _db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS history_unique ON history (track_key, played_at)',
    );
    _seqCounter = [
      for (final table in [
        'tracks',
        'likes',
        'playlists',
        'playlist_items',
        'history',
      ])
        (_db.select('SELECT MAX(seq) AS m FROM $table').first['m'] as int?) ??
            0,
    ].reduce((a, b) => a > b ? a : b);
    // Rows from before change numbers existed have seq 0, and "changed
    // after N" never included them: likes from the first versions didn't
    // reach other devices. Number them now (once; the order is kept).
    for (final table in [
      'tracks',
      'likes',
      'playlists',
      'playlist_items',
      'history',
    ]) {
      final old = _db
          .select('SELECT rowid AS r FROM $table WHERE seq = 0 ORDER BY rowid')
          .map((r) => r['r'] as int)
          .toList();
      if (old.isEmpty) continue;
      _db.execute('BEGIN');
      for (final r in old) {
        _db.execute('UPDATE $table SET seq = ? WHERE rowid = ?', [_nextSeq, r]);
      }
      _db.execute('COMMIT');
    }
  }

  /// Raw SQL for tests.
  @visibleForTesting
  void debugExecute(String sql) => _db.execute(sql);

  int _seqCounter = 0;
  int get _nextSeq => ++_seqCounter;

  /// Highest local change number; peers use it as a sync cursor.
  int get currentSeq => _seqCounter;

  int _lastNow = 0;

  /// Wall-clock ms, but strictly increasing: two writes in the same
  /// millisecond still have an order (matters for sorting and for sync).
  int get _now {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastNow = now > _lastNow ? now : _lastNow + 1;
    return _lastNow;
  }

  void _saveTrack(Track t) {
    // A stale copy (an old queue, another device on an old version) must
    // not put an artist link back over the name it was fixed to.
    if (t.artist.startsWith('spotify:artist:')) {
      final r = _db.select(
        "SELECT json_extract(json, '\$.artist') AS a FROM tracks WHERE key = ?",
        [t.key],
      );
      final fixed = r.isEmpty ? null : r.first['a'] as String?;
      if (fixed != null && !fixed.startsWith('spotify:artist:')) {
        t = Track.fromJson({...t.toJson(), 'artist': fixed});
      }
    }
    _db.execute(
      'INSERT INTO tracks (key, json, updated_at, seq) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET json = excluded.json, '
      'updated_at = excluded.updated_at, seq = excluded.seq',
      [t.key, jsonEncode(t.toJson()), _now, _nextSeq],
    );
  }

  List<Track> _tracks(String sql, [List<Object?> args = const []]) => [
    for (final row in _db.select(sql, args))
      Track.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
  ];

  void _changed() => _changes.add(null);

  /// Gives a stored track a cover if it has none (imported Spotify tracks
  /// get one from their YouTube match).
  /// Imported tracks whose cover URL starts with [prefix] (repairs).
  List<Track> tracksWithArtworkPrefix(String prefix) => [
    for (final r in _db.select(
      "SELECT json FROM tracks WHERE key LIKE 'match:%' AND "
      "json_extract(json, '\$.artworkUrl') LIKE ?",
      ['$prefix%'],
    ))
      Track.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>),
  ];

  /// Tracks whose artist starts with [prefix] (repairs).
  List<Track> tracksWithArtistPrefix(String prefix) => [
    for (final r in _db.select(
      "SELECT json FROM tracks WHERE json_extract(json, '\$.artist') LIKE ?",
      ['$prefix%'],
    ))
      Track.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>),
  ];

  /// Corrects a track's artist (synced to the other devices).
  void setArtist(Track t, String artist) {
    final rows = _db.select('SELECT json FROM tracks WHERE key = ?', [t.key]);
    if (rows.isEmpty) return;
    final json =
        jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
    if (json['artist'] == artist) return;
    json['artist'] = artist;
    _db.execute(
      'UPDATE tracks SET json = ?, updated_at = ?, seq = ? WHERE key = ?',
      [jsonEncode(json), _now, _nextSeq, t.key],
    );
    _changed();
  }

  void fillArtwork(Track t, String url) {
    final rows = _db.select('SELECT json FROM tracks WHERE key = ?', [t.key]);
    if (rows.isEmpty) return;
    final json =
        jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
    final had = json['artworkUrl'] as String?;
    // A YouTube thumbnail came from an earlier (maybe wrong) match: a new
    // match replaces it. Covers from Spotify/Yandex stay.
    if (had != null &&
        (!had.startsWith('https://i.ytimg.com/') || had == url)) {
      return;
    }
    json['artworkUrl'] = url;
    _db.execute(
      'UPDATE tracks SET json = ?, updated_at = ?, seq = ? WHERE key = ?',
      [jsonEncode(json), _now, _nextSeq, t.key],
    );
    _changed();
  }

  // --- Likes ------------------------------------------------------------------

  bool isLiked(Track t) => _db.select(
    'SELECT 1 FROM likes WHERE track_key = ? AND deleted = 0',
    [t.key],
  ).isNotEmpty;

  void setLiked(Track t, bool liked) {
    _saveTrack(t);
    _db.execute(
      'INSERT INTO likes (track_key, liked_at, deleted, updated_at, seq) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(track_key) DO UPDATE SET deleted = excluded.deleted, '
      'updated_at = excluded.updated_at, seq = excluded.seq, '
      'liked_at = CASE WHEN excluded.deleted = 0 THEN excluded.liked_at ELSE liked_at END',
      [t.key, _now, liked ? 0 : 1, _now, _nextSeq],
    );
    _changed();
  }

  /// Likes many tracks at once (an imported library), keeping their order:
  /// [newestFirst] the way services list them. Already liked ones are left
  /// as they are. Returns how many were added.
  int likeMany(List<Track> newestFirst) {
    final have = likedKeys();
    final fresh = [
      for (final t in newestFirst)
        if (!have.contains(t.key)) t,
    ];
    if (fresh.isEmpty) return 0;
    _db.execute('BEGIN');
    try {
      // Older than anything liked so far, newest of them first.
      final oldest = _db
          .select('SELECT MIN(liked_at) AS m FROM likes')
          .first['m'];
      final base =
          (oldest as int? ?? DateTime.now().millisecondsSinceEpoch) - 1;
      for (final (i, t) in fresh.indexed) {
        _saveTrack(t);
        _db.execute(
          'INSERT INTO likes (track_key, liked_at, deleted, updated_at, seq) '
          'VALUES (?, ?, 0, ?, ?) ON CONFLICT(track_key) DO UPDATE SET '
          'deleted = 0, liked_at = excluded.liked_at, '
          'updated_at = excluded.updated_at, seq = excluded.seq',
          [t.key, base - i, _now, _nextSeq],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _changed();
    return fresh.length;
  }

  List<Track> likedTracks() => _tracks(
    'SELECT t.json FROM likes l JOIN tracks t ON t.key = l.track_key '
    'WHERE l.deleted = 0 ORDER BY l.liked_at DESC',
  );

  /// Moves [ordered]\[from] to index [to] (after removal) among liked
  /// songs shown as [ordered] (newest first). The song takes a like time
  /// between its new neighbours; when they're too close (songs liked
  /// together in an import), the list is renumbered with room to spare.
  void moveLiked(List<Track> ordered, int from, int to) {
    if (from == to || from < 0 || from >= ordered.length) return;
    final list = List.of(ordered);
    final moved = list.removeAt(from);
    to = to.clamp(0, list.length);
    list.insert(to, moved);
    int at(Track t) =>
        (_db.select('SELECT liked_at FROM likes WHERE track_key = ?', [
              t.key,
            ]).firstOrNull?['liked_at']
            as int?) ??
        0;
    void set(Track t, int likedAt) => _db.execute(
      'UPDATE likes SET liked_at = ?, updated_at = ?, seq = ? '
      'WHERE track_key = ?',
      [likedAt, _now, _nextSeq, t.key],
    );
    final above = to > 0 ? at(list[to - 1]) : null; // newer
    final below = to < list.length - 1 ? at(list[to + 1]) : null; // older
    _db.execute('BEGIN');
    try {
      if (above == null) {
        set(moved, (below ?? 0) + 1000);
      } else if (below == null) {
        set(moved, above - 1000);
      } else if (above - below >= 2) {
        set(moved, below + (above - below) ~/ 2);
      } else {
        final top = at(list.first) + 1000;
        for (var i = 0; i < list.length; i++) {
          set(list[i], top - i * 1000);
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _changed();
  }

  Set<String> likedKeys() => {
    for (final r in _db.select('SELECT track_key FROM likes WHERE deleted = 0'))
      r['track_key'] as String,
  };

  // --- Playlists --------------------------------------------------------------

  String createPlaylist(String name) {
    final id = _uuid.v4();
    _db.execute(
      'INSERT INTO playlists (id, name, created_at, updated_at, seq) VALUES (?, ?, ?, ?, ?)',
      [
        id,
        name.trim().isEmpty ? 'Новый плейлист'.tr : name.trim(),
        _now,
        _now,
        _nextSeq,
      ],
    );
    _changed();
    return id;
  }

  void renamePlaylist(String id, String name) {
    _db.execute(
      'UPDATE playlists SET name = ?, updated_at = ?, seq = ? WHERE id = ?',
      [name.trim(), _now, _nextSeq, id],
    );
    _changed();
  }

  void deletePlaylist(String id) {
    _db.execute(
      'UPDATE playlists SET deleted = 1, updated_at = ?, seq = ? WHERE id = ?',
      [_now, _nextSeq, id],
    );
    _changed();
  }

  List<Playlist> playlists() => [
    for (final r in _db.select('''
      SELECT p.id, p.name,
        (SELECT COUNT(*) FROM playlist_items i WHERE i.playlist_id = p.id AND i.deleted = 0) AS count,
        (SELECT t.json FROM playlist_items i JOIN tracks t ON t.key = i.track_key
           WHERE i.playlist_id = p.id AND i.deleted = 0 ORDER BY i.position LIMIT 1) AS first
      FROM playlists p WHERE p.deleted = 0 ORDER BY p.created_at DESC
    '''))
      Playlist(
        id: r['id'] as String,
        name: r['name'] as String,
        count: r['count'] as int,
        coverUrl: r['first'] == null
            ? null
            : (jsonDecode(r['first'] as String)
                      as Map<String, dynamic>)['artworkUrl']
                  as String?,
      ),
  ];

  Playlist? playlist(String id) {
    for (final p in playlists()) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds tracks to the end; returns how many were new to the playlist.
  int addToPlaylist(String playlistId, List<Track> tracks) {
    final maxPos =
        _db.select(
              'SELECT MAX(position) AS m FROM playlist_items WHERE playlist_id = ?',
              [playlistId],
            ).first['m']
            as num? ??
        0;
    var pos = maxPos.toDouble();
    var added = 0;
    for (final t in tracks) {
      _saveTrack(t);
      final existed = _db.select(
        'SELECT deleted FROM playlist_items WHERE playlist_id = ? AND track_key = ?',
        [playlistId, t.key],
      );
      if (existed.isNotEmpty && existed.first['deleted'] == 0) continue;
      pos += 1;
      added++;
      _db.execute(
        'INSERT INTO playlist_items (playlist_id, track_key, position, deleted, updated_at, seq) '
        'VALUES (?, ?, ?, 0, ?, ?) ON CONFLICT(playlist_id, track_key) DO UPDATE SET '
        'deleted = 0, position = excluded.position, updated_at = excluded.updated_at, '
        'seq = excluded.seq',
        [playlistId, t.key, pos, _now, _nextSeq],
      );
    }
    _db.execute('UPDATE playlists SET updated_at = ?, seq = ? WHERE id = ?', [
      _now,
      _nextSeq,
      playlistId,
    ]);
    _changed();
    return added;
  }

  /// Moves [ordered]\[from] to index [to] (after removal) in a playlist
  /// shown as [ordered]. Only the moved item changes: it gets a position
  /// between its new neighbours (synced like any edit).
  void movePlaylistItem(
    String playlistId,
    List<Track> ordered,
    int from,
    int to,
  ) {
    if (from == to || from < 0 || from >= ordered.length) return;
    final list = List.of(ordered);
    final moved = list.removeAt(from);
    to = to.clamp(0, list.length);
    list.insert(to, moved);
    double posOf(Track t) =>
        (_db.select(
                  'SELECT position FROM playlist_items '
                  'WHERE playlist_id = ? AND track_key = ?',
                  [playlistId, t.key],
                ).firstOrNull?['position']
                as num?)
            ?.toDouble() ??
        0;
    final before = to > 0 ? posOf(list[to - 1]) : null;
    final after = to < list.length - 1 ? posOf(list[to + 1]) : null;
    final pos = before != null && after != null
        ? (before + after) / 2
        : before != null
        ? before + 1
        : (after ?? 1) - 1;
    _db.execute(
      'UPDATE playlist_items SET position = ?, updated_at = ?, seq = ? '
      'WHERE playlist_id = ? AND track_key = ?',
      [pos, _now, _nextSeq, playlistId, moved.key],
    );
    _changed();
  }

  void removeFromPlaylist(String playlistId, Track t) {
    _db.execute(
      'UPDATE playlist_items SET deleted = 1, updated_at = ?, seq = ? '
      'WHERE playlist_id = ? AND track_key = ?',
      [_now, _nextSeq, playlistId, t.key],
    );
    _changed();
  }

  List<Track> playlistTracks(String playlistId) => _tracks(
    'SELECT t.json FROM playlist_items i JOIN tracks t ON t.key = i.track_key '
    'WHERE i.playlist_id = ? AND i.deleted = 0 ORDER BY i.position',
    [playlistId],
  );

  // --- History ----------------------------------------------------------------

  void recordPlay(Track t) {
    _saveTrack(t);
    _db.execute(
      'INSERT OR IGNORE INTO history (track_key, played_at, seq) VALUES (?, ?, ?)',
      [t.key, _now, _nextSeq],
    );
    _changed();
  }

  /// Most recent first, each track once.
  List<Track> recentlyPlayed({int limit = 50}) => _tracks(
    'SELECT t.json FROM (SELECT track_key, MAX(played_at) AS last FROM history '
    'GROUP BY track_key ORDER BY last DESC LIMIT ?) h JOIN tracks t ON t.key = h.track_key '
    'ORDER BY h.last DESC',
    [limit],
  );

  void clearHistory() {
    _db.execute('DELETE FROM history');
    _changed();
  }

  // --- Downloads (device-local, not synced) -----------------------------------

  String? downloadedPath(Track t) {
    final r = _db.select('SELECT path FROM downloads WHERE track_key = ?', [
      t.key,
    ]);
    return r.isEmpty ? null : r.first['path'] as String;
  }

  Set<String> downloadedKeys() => {
    for (final r in _db.select('SELECT track_key FROM downloads'))
      r['track_key'] as String,
  };

  void saveDownload(Track t, String path, int size) {
    _saveTrack(t);
    _db.execute(
      'INSERT OR REPLACE INTO downloads (track_key, path, size, created_at) VALUES (?, ?, ?, ?)',
      [t.key, path, size, _now],
    );
    _changed();
  }

  void removeDownload(Track t) {
    _db.execute('DELETE FROM downloads WHERE track_key = ?', [t.key]);
    _changed();
  }

  List<Track> downloadedTracks() => _tracks(
    'SELECT t.json FROM downloads d JOIN tracks t ON t.key = d.track_key '
    'ORDER BY d.created_at DESC',
  );

  int downloadsSize() =>
      (_db
              .select('SELECT COALESCE(SUM(size), 0) AS s FROM downloads')
              .first['s']
          as int?) ??
      0;

  // --- Local music folders ----------------------------------------------------

  List<({String path, String? bookmark})> folders() => [
    for (final r in _db.select(
      'SELECT path, bookmark FROM folders ORDER BY path',
    ))
      (path: r['path'] as String, bookmark: r['bookmark'] as String?),
  ];

  void addFolder(String path, {String? bookmark}) {
    _db.execute(
      'INSERT OR REPLACE INTO folders (path, bookmark) VALUES (?, ?)',
      [path, bookmark],
    );
    _changed();
  }

  void removeFolder(String path) {
    _db.execute('DELETE FROM folders WHERE path = ?', [path]);
    _db.execute('DELETE FROM local_files WHERE folder = ?', [path]);
    _changed();
  }

  /// Modification times of indexed files in [folder], to skip unchanged ones.
  Map<String, int> localFileTimes(String folder) => {
    for (final r in _db.select(
      'SELECT path, modified FROM local_files WHERE folder = ?',
      [folder],
    ))
      r['path'] as String: r['modified'] as int,
  };

  /// Replaces the index of [folder] with [files] (path → track, mtime).
  void replaceLocalFiles(String folder, Map<String, (Track, int)> files) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM local_files WHERE folder = ?', [folder]);
      for (final e in files.entries) {
        _db.execute(
          'INSERT OR REPLACE INTO local_files (path, folder, json, modified) VALUES (?, ?, ?, ?)',
          [e.key, folder, jsonEncode(e.value.$1.toJson()), e.value.$2],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    _changed();
  }

  List<Track> localTracks() =>
      [
        for (final r in _db.select(
          'SELECT json FROM local_files ORDER BY json',
        ))
          Track.fromJson(
            jsonDecode(r['json'] as String) as Map<String, dynamic>,
          ),
      ]..sort(
        (a, b) => '${a.artist} ${a.title}'.toLowerCase().compareTo(
          '${b.artist} ${b.title}'.toLowerCase(),
        ),
      );

  Track? localTrack(String path) {
    final r = _db.select('SELECT json FROM local_files WHERE path = ?', [path]);
    return r.isEmpty
        ? null
        : Track.fromJson(
            jsonDecode(r.first['json'] as String) as Map<String, dynamic>,
          );
  }

  // --- Sync -------------------------------------------------------------------

  String _meta(String key, String Function() init) {
    final r = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    if (r.isNotEmpty) return r.first['value'] as String;
    final v = init();
    _db.execute('INSERT INTO meta (key, value) VALUES (?, ?)', [key, v]);
    return v;
  }

  /// Device-local key/value settings (not synced).
  String? getMeta(String key) {
    final r = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  // --- Preferences that follow you to your other devices ------------------

  /// Settings keys kept in sync between devices (each a JSON object).
  static const syncedPrefs = ['appearance', 'audio_fx', 'wave_settings'];

  /// Appearance settings that belong to one device, never synced.
  static const devicePrefs = {
    'textScale',
    'notchIsland',
    'desktopWidget',
    'offlineCache',
  };

  final _prefsChanges = StreamController<void>.broadcast();

  /// The user changed a synced setting here (the relay sends it on).
  Stream<void> get prefsChanges => _prefsChanges.stream;

  /// Settings received from another device were applied here.
  final prefsApplied = StreamController<void>.broadcast();

  /// When the synced settings were last changed (ms since epoch; 0 =
  /// never on this device, so another device's win).
  int get prefsAt => int.tryParse(getMeta('prefs_at') ?? '') ?? 0;

  /// Call after the user changed a synced setting.
  void touchPrefs() {
    setMeta('prefs_at', '${DateTime.now().millisecondsSinceEpoch}');
    _prefsChanges.add(null);
  }

  /// The synced settings, as sent to other devices.
  Map<String, dynamic> exportPrefs() {
    final out = <String, dynamic>{'at': prefsAt};
    for (final k in syncedPrefs) {
      final raw = getMeta(k);
      if (raw == null) continue;
      try {
        final j = Map<String, dynamic>.of(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
        if (k == 'appearance') {
          j.removeWhere((key, _) => devicePrefs.contains(key));
        }
        out[k] = j;
      } catch (_) {}
    }
    return out;
  }

  /// Takes [prefs] from another device if they're newer than ours.
  /// This device's own appearance keys (scale, notch…) stay as they are.
  bool importPrefs(Map<String, dynamic> prefs) {
    final at = prefs['at'] as int? ?? 0;
    if (at <= prefsAt) return false;
    for (final k in syncedPrefs) {
      final v = prefs[k];
      if (v is! Map) continue;
      final merged = Map<String, dynamic>.of(v.cast<String, dynamic>());
      if (k == 'appearance') {
        try {
          final mine = jsonDecode(getMeta(k) ?? '{}') as Map;
          for (final d in devicePrefs) {
            if (mine.containsKey(d)) merged[d] = mine[d];
          }
        } catch (_) {}
      }
      setMeta(k, jsonEncode(merged));
    }
    setMeta('prefs_at', '$at');
    prefsApplied.add(null);
    return true;
  }

  void setMeta(String key, String value) => _db.execute(
    'INSERT INTO meta (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  /// Stable id of this install, shared with paired devices.
  late final String deviceId = _meta('device_id', () => _uuid.v4());

  static const _syncTables = {
    'tracks': ['key', 'json', 'updated_at'],
    'likes': ['track_key', 'liked_at', 'deleted', 'updated_at'],
    'playlists': ['id', 'name', 'created_at', 'deleted', 'updated_at'],
    'playlist_items': [
      'playlist_id',
      'track_key',
      'position',
      'deleted',
      'updated_at',
    ],
  };
  static const _keys = {
    'tracks': ['key'],
    'likes': ['track_key'],
    'playlists': ['id'],
    'playlist_items': ['playlist_id', 'track_key'],
  };

  /// Everything changed locally after [sinceSeq], as JSON-able maps.
  Map<String, Object> exportChanges(int sinceSeq) => {
    for (final e in _syncTables.entries)
      e.key: [
        for (final r in _db.select(
          'SELECT ${e.value.join(', ')} FROM ${e.key} WHERE seq > ? ORDER BY seq',
          // Everything when starting from scratch, whatever its number.
          [sinceSeq <= 0 ? -1 : sinceSeq],
        ))
          {for (final c in e.value) c: r[c]},
      ],
    'history': [
      for (final r in _db.select(
        'SELECT track_key, played_at FROM history WHERE seq > ? ORDER BY seq',
        [sinceSeq <= 0 ? -1 : sinceSeq],
      ))
        {'track_key': r['track_key'], 'played_at': r['played_at']},
    ],
    'seq': _seqCounter,
  };

  /// Merges a peer's changes: per row, the newest `updated_at` wins;
  /// history is a set of plays, so it just unions. Returns rows applied.
  int applyChanges(Map<String, dynamic> changes) {
    var applied = 0;
    _db.execute('BEGIN');
    try {
      for (final e in _syncTables.entries) {
        final cols = e.value;
        final keys = _keys[e.key]!;
        final where = keys.map((k) => '$k = ?').join(' AND ');
        for (final row in (changes[e.key] as List? ?? const []).cast<Map>()) {
          final existing = _db.select(
            'SELECT updated_at FROM ${e.key} WHERE $where',
            [for (final k in keys) row[k]],
          );
          final incoming = row['updated_at'] as int;
          if (existing.isNotEmpty &&
              (existing.first['updated_at'] as int) >= incoming) {
            continue;
          }
          _db.execute(
            'INSERT OR REPLACE INTO ${e.key} (${cols.join(', ')}, seq) '
            'VALUES (${List.filled(cols.length + 1, '?').join(', ')})',
            [for (final c in cols) row[c], _nextSeq],
          );
          // Keep our clock ahead of anything we've seen, so a later local
          // edit always beats the remote one.
          if (incoming > _lastNow) _lastNow = incoming;
          applied++;
        }
      }
      for (final row in (changes['history'] as List? ?? const []).cast<Map>()) {
        _db.execute(
          'INSERT OR IGNORE INTO history (track_key, played_at, seq) VALUES (?, ?, ?)',
          [row['track_key'], row['played_at'], _nextSeq],
        );
        applied += _db.updatedRows;
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    if (applied > 0) _changed();
    return applied;
  }

  // Paired devices.

  List<Peer> peers() => [
    for (final r in _db.select('SELECT * FROM peers ORDER BY name'))
      Peer(
        id: r['id'] as String,
        name: r['name'] as String,
        platform: r['platform'] as String,
        token: r['token'] as String,
        sentSeq: r['sent_seq'] as int,
        recvSeq: r['recv_seq'] as int,
        host: r['host'] as String?,
        port: r['port'] as int?,
      ),
  ];

  Peer? peer(String id) => peers().where((p) => p.id == id).firstOrNull;

  void savePeer(Peer p) {
    _db.execute(
      'INSERT INTO peers (id, name, platform, token, sent_seq, recv_seq, host, port) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
      'platform = excluded.platform, token = excluded.token, sent_seq = excluded.sent_seq, '
      'recv_seq = excluded.recv_seq, host = excluded.host, port = excluded.port',
      [p.id, p.name, p.platform, p.token, p.sentSeq, p.recvSeq, p.host, p.port],
    );
    _changed();
  }

  void removePeer(String id) {
    _db.execute('DELETE FROM peers WHERE id = ?', [id]);
    _changed();
  }

  void dispose() {
    _changes.close();
    _db.close();
  }
}
