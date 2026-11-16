import 'dart:async';

import '../models/track.dart';
import 'match_source.dart';
import 'music_source.dart';
import 'soundcloud_source.dart';

/// Plays a song from SoundCloud when YouTube won't (blocked on this
/// network, removed, region-locked): the same song, found by title,
/// artist and length, so the queue goes on instead of skipping it.
class StandIn {
  StandIn(this._soundcloud);

  final SoundCloudSource _soundcloud;

  /// Found versions by the wanted song's key (null: none good enough).
  final _found = <String, Track?>{};

  /// Titles of songs that played from SoundCloud instead, for a notice.
  static final used = StreamController<String>.broadcast();

  /// Lowest score that is still the same song: title and artist match
  /// (60 + 25), minus a little for packaging words.
  static const _minScore = 70.0;

  /// The SoundCloud version of [wanted], if there's a convincing one.
  Future<Track?> find(Track wanted) async {
    if (_found.containsKey(wanted.key)) return _found[wanted.key];
    final title = MatchSource.coreTitle(wanted.title);
    final found = await _soundcloud.search(
      '${wanted.artist} $title'.trim(),
      limit: 15,
    );
    Track? best;
    var bestScore = _minScore;
    final want = MatchSource.norm(MatchSource.coreTitle(wanted.title))
        .split(' ')
        .where((w) => w.isNotEmpty);
    for (final raw in found) {
      // Uploads by fans read "Artist - Song": compare the song part.
      final t = _split(raw);
      // Fancy letters (𝙨𝙥𝙚𝙚𝙙 𝙪𝙥) mark sped-up and slowed edits.
      if (RegExp(r'[\u{1D400}-\u{1D7FF}]', unicode: true).hasMatch(raw.title)) {
        continue;
      }
      final have = MatchSource.norm(t.title).split(' ').toSet();
      if (!want.every(have.contains)) continue;
      if (MatchSource.extraWords(wanted, t.title).length > 1) continue;
      final s = MatchSource.score(wanted, (track: t, official: false));
      // A very different length is another recording or a preview.
      final wd = wanted.duration?.inSeconds, td = t.duration?.inSeconds;
      if (wd != null && td != null && wd > 0 && (wd - td).abs() > 20) {
        continue;
      }
      if (s >= bestScore) {
        best = raw;
        bestScore = s;
      }
    }
    if (_found.length > 200) _found.remove(_found.keys.first);
    return _found[wanted.key] = best;
  }

  static Track _split(Track t) {
    final dash = RegExp(r'\s[-–—]\s').firstMatch(t.title);
    if (dash == null) return t;
    return Track(
      id: t.id,
      source: t.source,
      title: t.title.substring(dash.end).trim(),
      artist: t.title.substring(0, dash.start).trim(),
      duration: t.duration,
    );
  }

  Future<StreamInfo> resolve(Track wanted) async {
    final t = await find(wanted);
    if (t == null) {
      throw StateError('Нет замены на SoundCloud для ${wanted.title}');
    }
    final info = await _soundcloud.resolveStream(t);
    used.add(wanted.title);
    return info;
  }
}
