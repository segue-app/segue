/// Platform a track comes from. New sources add a value here and an
/// implementation of [MusicSource].
enum SourceKind {
  youtube,
  soundcloud,

  /// Imported from a service we can't stream (Spotify, Yandex Music): only
  /// artist/title/duration are known; audio is matched on YouTube at play
  /// time. [Track.id] is "artist — title".
  match,

  /// A file on this device (the user's own music folder). [Track.id] is the
  /// absolute path.
  local;

  /// Sources the user can search directly.
  bool get searchable => this != match && this != local;
}

/// A playable track, independent of where it comes from.
class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.duration,
  });

  /// Source-specific id (YouTube video id, SoundCloud track id).
  final String id;
  final SourceKind source;
  final String title;
  final String artist;
  final String? artworkUrl;
  final Duration? duration;

  /// Unique across sources; used for queue, likes and sync.
  String get key => '${source.name}:$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'title': title,
    'artist': artist,
    'artworkUrl': artworkUrl,
    'durationMs': duration?.inMilliseconds,
  };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
    id: j['id'] as String,
    source: SourceKind.values.byName(j['source'] as String),
    title: j['title'] as String,
    artist: j['artist'] as String,
    artworkUrl: j['artworkUrl'] as String?,
    duration: j['durationMs'] == null
        ? null
        : Duration(milliseconds: j['durationMs'] as int),
  );

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
