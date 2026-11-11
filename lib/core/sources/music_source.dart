import '../models/track.dart';

/// A place music can be searched and streamed from.
///
/// Everything runs on the user's device: Segue never hosts or proxies audio
/// through a server of its own.
abstract class MusicSource {
  SourceKind get kind;

  /// Human-readable name shown in the UI.
  String get label;

  Future<List<Track>> search(String query, {int limit = 20});

  /// Resolves a playable stream for [track]. URLs expire, so resolve right
  /// before playback instead of storing them.
  Future<StreamInfo> resolveStream(Track track);
}

/// Where and how to fetch a track's audio.
class StreamInfo {
  const StreamInfo(
    this.url, {
    this.contentLength,
    this.mimeType,
    this.chunked = false,
    this.hls = false,
    this.duration,
  });

  final Uri url;
  final int? contentLength;
  final String? mimeType;

  /// The server only answers small byte ranges (YouTube), so the player must
  /// fetch the file piece by piece instead of in one request.
  final bool chunked;

  /// [url] is an HLS playlist (.m3u8) even if the path does not say so.
  final bool hls;

  /// Exact duration when the source knows it; some containers make the
  /// platform player misjudge it.
  final Duration? duration;
}

/// A source that can also hand out one complete audio file (for offline),
/// not just a stream.
abstract interface class FileSource {
  Future<StreamInfo> resolveFile(Track track);
}
