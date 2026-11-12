import '../models/track.dart';
import 'music_source.dart';
import 'youtube_source.dart';

/// A YouTube video considered for an imported song.
typedef MatchCandidate = ({Track track, bool official});

/// Plays tracks imported from services we can't stream (Spotify, Yandex
/// Music) by finding the same song on YouTube right before it plays.
///
/// Matching lazily means importing a 100-track playlist costs nothing up
/// front, and YouTube only sees one search per song actually played.
class MatchSource implements MusicSource, FileSource {
  MatchSource(this._youtube);

  final YouTubeSource _youtube;
  final _cache = <String, Track>{};
  final _pending = <String, Future<Track>>{};

  /// Called once a match is found (or chosen by hand), e.g. to remember it
  /// and to save its cover for the imported track.
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
  Future<StreamInfo> resolveStream(Track track) =>
      _resolve(track, _youtube.resolveStream);

  @override
  Future<StreamInfo> resolveFile(Track track) =>
      _resolve(track, _youtube.resolveFile);

  /// The match, or when YouTube won't play it (removed, age or region
  /// locked) the next best versions.
  Future<StreamInfo> _resolve(
    Track track,
    Future<StreamInfo> Function(Track) open,
  ) async {
    final match = await findMatch(track);
    try {
      return await open(match);
    } catch (_) {
      final alts = _alternatives[track.key] ?? await candidates(track);
      for (final c in alts.where((c) => c.track.id != match.id).take(3)) {
        try {
          final info = await open(c.track);
          choose(track, c.track);
          return info;
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Ranked candidates of recent searches, for falling back.
  final _alternatives = <String, List<MatchCandidate>>{};

  /// The YouTube track [track] was matched to, if it was already.
  Track? matched(Track track) => _cache[track.key] ?? recall?.call(track.key);

  /// The user picked another version: it plays from now on.
  void choose(Track imported, Track match) {
    _cache[imported.key] = match;
    onMatched?.call(imported, match);
  }

  Future<Track> findMatch(Track track) {
    final cached = _cache[track.key] ?? recall?.call(track.key);
    if (cached != null) return Future.value(_cache[track.key] = cached);
    // Prefetch and play may ask at once: one search.
    return _pending[track.key] ??= _find(track).whenComplete(() {
      _pending.remove(track.key);
    });
  }

  Future<Track> _find(Track track) async {
    final found = await candidates(track);
    if (found.isEmpty) {
      throw StateError('Не нашёл «${track.title}» на YouTube');
    }
    _alternatives[track.key] = found;
    if (_alternatives.length > 50) {
      _alternatives.remove(_alternatives.keys.first);
    }
    final best = found.first.track;
    _cache[track.key] = best;
    onMatched?.call(track, best);
    return best;
  }

  /// YouTube versions of [track], best first. A second search runs when
  /// the first finds nothing convincing.
  Future<List<MatchCandidate>> candidates(Track track) async {
    final core = coreTitle(track.title);
    var found = await _youtube.searchDetailed(
      '${track.artist} $core',
      limit: 15,
    );
    var ranked = rank(track, found);
    if (ranked.isEmpty || score(track, ranked.first) < 70) {
      final more = await _youtube
          .searchDetailed('${track.artist} - ${track.title} audio', limit: 15)
          .catchError((Object _) => <MatchCandidate>[]);
      final seen = {for (final c in found) c.track.id};
      found = [...found, ...more.where((c) => seen.add(c.track.id))];
      ranked = rank(track, found);
    }
    return ranked;
  }

  /// [found] sorted best first, without the ones that clearly aren't the
  /// song (none of its title words).
  static List<MatchCandidate> rank(Track wanted, List<MatchCandidate> found) {
    final scored = [
      for (final c in found)
        if (_titleCover(wanted, c.track) > 0) (c, score(wanted, c)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final s in scored) s.$1];
  }

  /// Picks the best candidate (exposed for tests).
  static Track pickBest(Track wanted, List<Track> candidates) {
    final ranked = rank(wanted, [
      for (final t in candidates) (track: t, official: false),
    ]);
    return ranked.isEmpty ? candidates.first : ranked.first.track;
  }

  // --- scoring ----------------------------------------------------------------

  /// Versions the original isn't, unless the wanted title says so.
  static const _variants = [
    'live',
    'cover',
    'remix',
    'karaoke',
    'instrumental',
    'slowed',
    'sped up',
    'speed up',
    'reverb',
    '8d',
    'nightcore',
    'reaction',
    'concert',
    'acoustic',
    'mashup',
    'bass boosted',
    'tiktok',
    'kaver',
    'remiks',
    'minus',
    'karaoke',
    'kontsert',
    'zhivoi',
    'akustika',
    'remake',
    'reupload',
    'rare',
    'demo',
    'arena',
    'tour',
    'festival',
    'repetitsiia',
    'zhenskaia versiia',
    'piano',
    'guitar',
    'tutorial',
    'razbor',
    'na gitare',
    'parodiia',
    'parody',
    'version',
    'versiia',
    'rerecorded',
    're recorded',
    'taylors version',
  ];

  /// Lyric videos usually carry the right audio, but the original is
  /// better.
  static const _lyricWords = ['lyrics', 'lyric', 'tekst', 'tekst pesni'];

  /// Words around the song in video titles that say nothing about which
  /// version it is.
  static const _noise = {
    'official', 'video', 'audio', 'music', 'clip', 'klip', 'lyrics',
    'lyric', 'hd', 'hq', '4k', 'feat', 'ft', 'premiere', 'premera', 'treka',
    'klipa', 'the', 'a', 'i', 'and', 'v', 'na', 'ofitsialnyi', 'pesni',
    'visualizer', 'tekst', 'mv', 'topic', 'prod', 'by', 'album',
    'single', 'remastered', 'remaster', 'edit', 'radio', 'original', 'mix',
    'explicit', 'with', 'x',
  };

  static final _variantsNorm = {for (final v in _variants) norm(v)};
  static final _noiseNorm = {for (final w in _noise) norm(w)};

  /// Higher is better: same words in the title, the artist, the length,
  /// the artist's own channel; covers, live versions etc. lose.
  static double score(Track wanted, MatchCandidate c) {
    final t = c.track;
    final wantedText = norm('${wanted.title} ${wanted.artist}');
    final text = norm('${t.title} ${t.artist}');
    final textWords = text.split(' ').toSet();
    var s = 60 * _titleCover(wanted, t);
    final artistWords = _words(wanted.artist).where((w) => w.length > 1);
    if (artistWords.isEmpty || artistWords.any(textWords.contains)) s += 25;
    final wd = wanted.duration?.inSeconds, cd = t.duration?.inSeconds;
    if (wd != null && cd != null && wd > 0) {
      final diff = (wd - cd).abs();
      s += diff <= 2
          ? 20
          : diff <= 6
          ? 12
          : diff <= 15
          ? 4
          : -(diff.clamp(0, 120) / 2);
    }
    if (c.official) s += 12;
    for (final v in _variantsNorm) {
      final inText = _has(text, v), inWanted = _has(wantedText, v);
      // A remix where the original is wanted, or the other way round.
      if (inText && !inWanted) s -= 40;
      if (inWanted && !inText) s -= 30;
    }
    if (_lyricWords.any((w) => _has(text, norm(w))) &&
        !_lyricWords.any((w) => _has(wantedText, norm(w)))) {
      s -= 8;
    }
    // A date in the title: a concert recording.
    if (RegExp(r'\b\d{1,2}[./]\d{1,2}[./](19|20)?\d\d\b').hasMatch(t.title)) {
      s -= 30;
    }
    // Words that are neither the song's nor packaging: someone else's
    // channel, "part 2", another song in a medley…
    final known = {..._words(wanted.title), ..._words(wanted.artist)};
    final extra = _words(
      t.title,
    ).where((w) => !known.contains(w) && !_noiseNorm.contains(w) && !_isYear(w));
    s -= (extra.length * 4).clamp(0, 24);
    return s;
  }

  /// Share of the wanted title's words found in the candidate.
  static double _titleCover(Track wanted, Track t) {
    final want = _words(coreTitle(wanted.title));
    if (want.isEmpty) return 1;
    final have = norm('${t.title} ${t.artist}').split(' ').toSet();
    return want.where(have.contains).length / want.length;
  }

  static bool _has(String text, String phrase) =>
      ' $text '.contains(' $phrase ');

  static bool _isYear(String w) => RegExp(r'^(19|20)\d\d$').hasMatch(w);

  static Set<String> _words(String s) =>
      norm(s).split(' ').where((w) => w.isNotEmpty).toSet();

  /// The title without "(feat. …)", "- Remastered 2011", "[Explicit]"…
  static String coreTitle(String title) {
    var t = title.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
    final dash = RegExp(
      r'\s[-–—]\s.*(remaster|version|edit|mix|mono|stereo|live|from|feat|'
      r'версия|запись).*$',
      caseSensitive: false,
    );
    t = t.replaceAll(dash, ' ');
    t = t.replaceAll(RegExp(r'\s(feat|ft)\.?\s.*$', caseSensitive: false), ' ');
    return t.trim().isEmpty ? title : t.trim();
  }

  /// Lowercase Latin words: Cyrillic is transliterated, so "Баста" and
  /// "Basta" compare equal.
  static String norm(String s) {
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(_translit[ch] ?? ch);
    }
    return b
        .toString()
        .replaceAll(RegExp(r"['’`]"), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        // Transliterations differ ("Кайф" is Kaif, Kayf or Kajf): fold.
        .replaceAll('kh', 'h')
        .replaceAll('ck', 'k')
        .replaceAll(RegExp('[yj]'), 'i')
        .replaceAll('w', 'v')
        .replaceAll('q', 'k')
        .trim();
  }

  static const _translit = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'і': 'i',
    'ї': 'i', 'є': 'e', 'ү': 'u', 'ө': 'o', 'ң': 'n', 'қ': 'k', 'ғ': 'g',
    'ұ': 'u', 'ә': 'a', 'һ': 'h',
  };
}
