import '../models/track.dart';
import 'music_source.dart';
import 'youtube_source.dart';

/// Plays tracks imported from services we can't stream (Spotify, Yandex
/// Music) by finding the same song on YouTube right before it plays.
///
/// Matching lazily means importing a 100-track playlist costs nothing up
/// front, and YouTube only sees one search per song actually played.
class MatchSource implements MusicSource, FileSource {
  MatchSource(this._youtube);

  final YouTubeSource _youtube;
  final _cache = <String, Track>{};

  /// Called once a match is found, e.g. to save its cover for the
  /// imported track (Spotify embeds don't include track artwork).
  void Function(Track imported, Track match)? onMatched;

  /// Matches remembered between launches (set in main()).
  Track? Function(String key)? recall;

  @override
  SourceKind get kind => SourceKind.match;

  @override
  String get label => 'Подбор';

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async => const [];

  @override
  Future<StreamInfo> resolveStream(Track track) async {
    final match = await findMatch(track);
    return _youtube.resolveStream(match);
  }

  @override
  Future<StreamInfo> resolveFile(Track track) async =>
      _youtube.resolveFile(await findMatch(track));

  Future<Track> findMatch(Track track) async {
    final cached = _cache[track.key] ?? recall?.call(track.key);
    if (cached != null) return _cache[track.key] = cached;
    final candidates = await _youtube.search(
      '${track.artist} ${track.title}',
      limit: 8,
    );
    if (candidates.isEmpty) {
      throw StateError('Не нашёл «${track.title}» на YouTube');
    }
    final best = pickBest(track, candidates);
    _cache[track.key] = best;
    onMatched?.call(track, best);
    return best;
  }

  /// Picks the candidate closest in length, avoiding versions the original
  /// isn't (live, cover, remix, sped up...). Exposed for tests.
  static Track pickBest(Track wanted, List<Track> candidates) {
    final wantedText = '${wanted.title} ${wanted.artist}'.toLowerCase();
    const variants = [
      'live',
      'cover',
      'remix',
      'karaoke',
      'instrumental',
      'slowed',
      'sped up',
      'reverb',
      '8d',
      'nightcore',
      'reaction',
      'lyrics video',
      'concert',
      'кавер',
      'ремикс',
      'минус',
      'караоке',
      'концерт',
    ];
    final artistWords = wanted.artist
        .toLowerCase()
        .split(RegExp(r'[\s,&]+'))
        .where((w) => w.length > 2);

    double score(Track c) {
      final text = '${c.title} ${c.artist}'.toLowerCase();
      var s = 0.0;
      final wd = wanted.duration?.inSeconds, cd = c.duration?.inSeconds;
      s += (wd != null && cd != null) ? (wd - cd).abs().toDouble() : 15;
      for (final v in variants) {
        if (text.contains(v) && !wantedText.contains(v)) s += 40;
      }
      if (!artistWords.any(text.contains)) s += 25;
      // Official uploads: "Artist - Topic" channels and "Official Audio".
      if (text.contains('official audio') ||
          c.artist.toLowerCase() == wanted.artist.toLowerCase()) {
        s -= 5;
      }
      return s;
    }

    return (List.of(
      candidates,
    )..sort((a, b) => score(a).compareTo(score(b)))).first;
  }
}
