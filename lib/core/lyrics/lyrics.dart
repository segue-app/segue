import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import '../player/player.dart';
import '../sources/match_source.dart';
import '../sources/sources.dart';

class LyricLine {
  const LyricLine(this.time, this.text, {this.words});

  final Duration time;
  final String text;

  /// Per-word timing from enhanced LRC (`<mm:ss.xx>word`), if the file had it.
  final List<LyricWord>? words;
}

class LyricWord {
  const LyricWord(this.text, this.start, this.end);

  final String text;
  final Duration start;
  final Duration end;

  /// 0 before the word, 1 once sung, in between while it is being sung.
  double progressAt(Duration t) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start).inMicroseconds / (end - start).inMicroseconds;
  }
}

class Lyrics {
  Lyrics({
    required this.lines,
    required this.synced,
    this.shift = Duration.zero,
    this.length,
    this.source = '',
  });

  /// For plain (unsynced) lyrics every line has time zero.
  final List<LyricLine> lines;
  final bool synced;

  /// How much later than their timestamps the lines come in what plays:
  /// a music video's spoken intro before the song starts.
  final Duration shift;

  /// Length of the recording the timings were made for, if known.
  final Duration? length;

  /// Where they came from (shown small under the lyrics).
  final String source;

  /// Real per-word timing (karaoke), not estimated.
  bool get wordSynced => lines.any((l) => l.words != null);

  Lyrics withShift(Duration d) => Lyrics(
    lines: lines,
    synced: synced,
    shift: d,
    length: length,
    source: source,
  );

  /// Index of the line being sung at [position], or -1 before the first.
  int lineAt(Duration position) {
    if (!synced) return -1;
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  late final List<List<LyricWord>> _words = [
    for (var i = 0; i < lines.length; i++) lines[i].words ?? _estimateWords(i),
  ];

  /// Word timings for line [i]: real ones when the LRC had them, otherwise
  /// estimated by spreading the line's sung time over its words by length
  /// (what big players do for tracks without word-level sync).
  List<LyricWord> wordsOf(int i) => _words[i];

  List<LyricWord> _estimateWords(int i) {
    final line = lines[i];
    final tokens = line.text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return const [];
    final next = i + 1 < lines.length
        ? lines[i + 1].time
        : line.time + const Duration(seconds: 6);
    final gap = (next - line.time).inMilliseconds;
    final letters = tokens.fold(0, (n, w) => n + w.length);
    // People rarely sing right up to the next line: cap by a typical pace.
    final singMs = [
      gap * 0.9,
      letters * 110.0 + 400,
    ].reduce((a, b) => a < b ? a : b);
    final totalWeight = tokens.fold(0, (n, w) => n + w.length + 1);
    var t = line.time.inMicroseconds.toDouble();
    return [
      for (final w in tokens)
        () {
          final len = singMs * 1000 * (w.length + 1) / totalWeight;
          final word = LyricWord(
            w,
            Duration(microseconds: t.round()),
            Duration(microseconds: (t + len).round()),
          );
          t += len;
          return word;
        }(),
    ];
  }

  /// Parses LRC text: `[mm:ss.xx] words`, several stamps per line allowed,
  /// and enhanced LRC word stamps `<mm:ss.xx>word`.
  static Lyrics parseLrc(String lrc) {
    final stamp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    final wordStamp = RegExp(r'<(\d+):(\d+(?:\.\d+)?)>');
    Duration at(Match m) => Duration(
      milliseconds:
          (int.parse(m.group(1)!) * 60000 + double.parse(m.group(2)!) * 1000)
              .round(),
    );

    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final stamps = stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final body = raw.substring(stamps.last.end);

      List<LyricWord>? words;
      final ws = wordStamp.allMatches(body).toList();
      if (ws.isNotEmpty) {
        words = [];
        for (var k = 0; k < ws.length; k++) {
          final textEnd = k + 1 < ws.length ? ws[k + 1].start : body.length;
          final text = body.substring(ws[k].end, textEnd).trim();
          if (text.isEmpty) continue;
          final start = at(ws[k]);
          final end = k + 1 < ws.length
              ? at(ws[k + 1])
              : start + const Duration(milliseconds: 600);
          words.add(LyricWord(text, start, end));
        }
      }
      final text = body
          .replaceAll(wordStamp, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      for (final m in stamps) {
        lines.add(
          LyricLine(at(m), text, words: stamps.length == 1 ? words : null),
        );
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(lines: lines, synced: true);
  }

  /// NetEase's word-timed format: `[lineStartMs,lineMs](wordStartMs,wordMs,0)word…`.
  static Lyrics parseYrc(String yrc) {
    final head = RegExp(r'^\[(\d+),(\d+)\]');
    final stamp = RegExp(r'\((\d+),(\d+),\d+\)');
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(yrc)) {
      final h = head.firstMatch(raw);
      if (h == null) continue; // credits come as JSON lines
      final body = raw.substring(h.end);
      final ws = stamp.allMatches(body).toList();
      final words = <LyricWord>[];
      final text = StringBuffer();
      for (var k = 0; k < ws.length; k++) {
        final end = k + 1 < ws.length ? ws[k + 1].start : body.length;
        final piece = body.substring(ws[k].end, end);
        text.write(piece);
        if (piece.trim().isEmpty) continue;
        final start = int.parse(ws[k].group(1)!);
        final dur = int.parse(ws[k].group(2)!);
        words.add(
          LyricWord(
            piece.trim(),
            Duration(milliseconds: start),
            Duration(milliseconds: start + dur),
          ),
        );
      }
      final line = text.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty || _isCredit(line)) continue;
      lines.add(
        LyricLine(
          Duration(milliseconds: int.parse(h.group(1)!)),
          line,
          words: words.isEmpty ? null : words,
        ),
      );
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(lines: lines, synced: true);
  }

  /// "作词 : …", "Producer: …" — who wrote it, not what's sung.
  static bool _isCredit(String line) => RegExp(
    r'^\s*(作词|作曲|编曲|制作|制作人|混音|录音|母带|和声|吉他|贝斯|鼓|弦乐|监制|出品|发行|'
    r'词|曲|OP|SP|Producer|Lyricist|Composer|Lyrics by|Composed by|Written by)'
    r'\s*[:：]',
    caseSensitive: false,
  ).hasMatch(line);

  static Lyrics plain(String text) => Lyrics(
    lines: [
      for (final l in const LineSplitter().convert(text))
        LyricLine(Duration.zero, l.trim()),
    ],
    synced: false,
  );
}

/// Finds lyrics on LRCLIB (open, free lyrics database with timestamps).
class LyricsService {
  LyricsService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _cache = <String, Lyrics?>{};

  /// Video titles carry noise: "(Official Video)", "[4K]", "ft. X", "| Topic".
  static String cleanQuery(Track t) {
    var title = t.title;
    title = title.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
    title = title.replaceAll(
      RegExp(
        r'\b(official|music|lyric|lyrics|video|audio|visualizer|hd|4k|mv)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    title = title.split('|').first;
    title = title.replaceAll(
      RegExp(r'\s+(ft\.?|feat\.?)\s.*$', caseSensitive: false),
      ' ',
    );
    final hasArtist =
        title.contains(' - ') ||
        title.toLowerCase().contains(t.artist.toLowerCase());
    final q = hasArtist ? title : '${t.artist} $title';
    return q.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Artist and song title as a lyrics service would name them.
  static ({String artist, String title}) nameOf(Track t) {
    final q = cleanQuery(t);
    final dash = RegExp(r'^(.+?)\s[-–—]\s(.+)$').firstMatch(q);
    if (dash != null && t.source != SourceKind.match) {
      return (artist: dash.group(1)!.trim(), title: dash.group(2)!.trim());
    }
    return (artist: t.artist, title: MatchSource.coreTitle(t.title));
  }

  /// How sure we are that a found song is [want] (0 = not it at all).
  static double similarity(
    ({String artist, String title}) want,
    Duration? wantLength,
    String title,
    String artist,
    Duration? length,
  ) {
    Set<String> words(String s) =>
        MatchSource.norm(s).split(' ').where((w) => w.isNotEmpty).toSet();
    final wantTitle = words(MatchSource.coreTitle(want.title));
    final got = words('${MatchSource.coreTitle(title)} $artist');
    if (wantTitle.isEmpty) return 0;
    final cover = wantTitle.where(got.contains).length / wantTitle.length;
    // And not a longer, different song that contains these words.
    final gotTitle = words(MatchSource.coreTitle(title));
    final extra = gotTitle.isEmpty
        ? 0.0
        : gotTitle.where((w) => !wantTitle.contains(w)).length /
              gotTitle.length;
    if (cover < 0.6 || extra > 0.5) return 0;
    final artistWords = words(want.artist).where((w) => w.length > 1);
    final gotArtist = words('$artist $title');
    final artistOk = artistWords.isEmpty || artistWords.any(gotArtist.contains);
    if (!artistOk) return 0;
    var s = 60 * cover + 20 - 20 * extra;
    if (wantLength != null && length != null) {
      final d = (wantLength - length).inSeconds.abs();
      s += d <= 3 ? 20 : (d <= 15 ? 5 : -(d.clamp(0, 60).toDouble()));
    }
    return s;
  }

  Future<Lyrics?> fetch(Track track) async {
    if (_cache.containsKey(track.key)) return _cache[track.key];
    final want = nameOf(track);
    // Both at once: NetEase often has word-by-word timing (karaoke),
    // LRCLIB is open and community-made, with line timing.
    final (ne, lrc) = await (
      _netease(want, track.duration).catchError((Object _) => null),
      _lrclib(track, want).catchError((Object _) => null),
    ).wait;
    Lyrics? result;
    if (ne != null && ne.wordSynced) {
      result = ne;
    } else if (lrc != null && lrc.synced) {
      result = lrc;
    } else {
      result = ne ?? lrc;
    }
    _cache[track.key] = result;
    return result;
  }

  static const _ua = {
    'User-Agent': 'Segue (https://github.com/segue-app/segue)',
  };

  Future<Lyrics?> _lrclib(
    Track track,
    ({String artist, String title}) want,
  ) async {
    final res = await _http
        .get(
          Uri.https('lrclib.net', '/api/search', {
            'track_name': want.title,
            'artist_name': want.artist,
          }),
          headers: _ua,
        )
        .timeout(const Duration(seconds: 10));
    var items = res.statusCode == 200
        ? (jsonDecode(res.body) as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    if (items.isEmpty) {
      // Free text finds songs whose fields are split differently.
      final res2 = await _http
          .get(
            Uri.https('lrclib.net', '/api/search', {'q': cleanQuery(track)}),
            headers: _ua,
          )
          .timeout(const Duration(seconds: 10));
      if (res2.statusCode == 200) {
        items = (jsonDecode(res2.body) as List).cast<Map<String, dynamic>>();
      }
    }
    double score(Map<String, dynamic> it) {
      if (it['instrumental'] == true) return 0;
      final d = (it['duration'] as num?)?.toDouble();
      final s = similarity(
        want,
        track.duration,
        it['trackName'] as String? ?? '',
        it['artistName'] as String? ?? '',
        d == null ? null : Duration(milliseconds: (d * 1000).round()),
      );
      return s == 0 ? 0 : s + (it['syncedLyrics'] != null ? 30 : 0);
    }

    final usable = [
      for (final it in items)
        if ((it['syncedLyrics'] ?? it['plainLyrics']) != null && score(it) > 0)
          it,
    ]..sort((a, b) => score(b).compareTo(score(a)));
    if (usable.isEmpty) return null;
    final best = usable.first;
    final d = (best['duration'] as num?)?.toDouble();
    final length = d == null
        ? null
        : Duration(milliseconds: (d * 1000).round());
    final l = best['syncedLyrics'] != null
        ? Lyrics.parseLrc(best['syncedLyrics'] as String)
        : Lyrics.plain(best['plainLyrics'] as String);
    return Lyrics(
      lines: l.lines,
      synced: l.synced,
      length: length,
      source: 'LRCLIB',
    );
  }

  Future<Lyrics?> _netease(
    ({String artist, String title}) want,
    Duration? length,
  ) async {
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/130.0 Safari/537.36',
      'Referer': 'https://music.163.com/',
    };
    final res = await _http
        .get(
          Uri.https('music.163.com', '/api/search/get', {
            's': '${want.artist} ${want.title}',
            'type': '1',
            'limit': '10',
          }),
          headers: headers,
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final songs =
        (((jsonDecode(res.body) as Map)['result'] as Map?)?['songs'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    double score(Map<String, dynamic> s) => similarity(
      want,
      length,
      s['name'] as String? ?? '',
      [
        for (final a in (s['artists'] as List? ?? const []))
          (a as Map)['name'] ?? '',
      ].join(' '),
      s['duration'] is int
          ? Duration(milliseconds: s['duration'] as int)
          : null,
    );
    final ranked = [
      for (final s in songs)
        if (score(s) > 0) s,
    ]..sort((a, b) => score(b).compareTo(score(a)));
    for (final song in ranked.take(2)) {
      final lr = await _http
          .get(
            Uri.https('music.163.com', '/api/song/lyric', {
              'id': '${song['id']}',
              'lv': '1',
              'yv': '1',
              'tv': '-1',
            }),
            headers: headers,
          )
          .timeout(const Duration(seconds: 8));
      if (lr.statusCode != 200) continue;
      final j = jsonDecode(lr.body) as Map<String, dynamic>;
      final yrc = (j['yrc'] as Map?)?['lyric'] as String?;
      final lrc = (j['lrc'] as Map?)?['lyric'] as String?;
      Lyrics? l;
      if (yrc != null && yrc.trim().isNotEmpty) {
        l = Lyrics.parseYrc(yrc);
      } else if (lrc != null && lrc.contains('[')) {
        final parsed = Lyrics.parseLrc(lrc);
        l = Lyrics(
          lines: [
            for (final x in parsed.lines)
              if (x.text.isNotEmpty && !Lyrics._isCredit(x.text)) x,
          ],
          synced: true,
        );
      }
      if (l == null || l.lines.length < 3) continue;
      // NetEase often opens with a "Song - Artist" title line.
      final name = MatchSource.norm(MatchSource.coreTitle(want.title));
      final lines = [
        for (var i = 0; i < l.lines.length; i++)
          if (!(i < 2 &&
              RegExp(r'\s[-–—]\s').hasMatch(l.lines[i].text) &&
              MatchSource.norm(l.lines[i].text).contains(name)))
            l.lines[i],
      ];
      return Lyrics(
        lines: lines,
        synced: true,
        length: song['duration'] is int
            ? Duration(milliseconds: song['duration'] as int)
            : null,
        source: 'NetEase',
      );
    }
    return null;
  }
}

final lyricsServiceProvider = Provider<LyricsService>((ref) => LyricsService());

final lyricsProvider = FutureProvider.family<Lyrics?, Track>((
  ref,
  track,
) async {
  final l = await ref.read(lyricsServiceProvider).fetch(track);
  if (l == null || !l.synced) return l;
  // A music video with a spoken intro: the song (and its lyrics) start
  // later than in the recording the timings were made for.
  final bounds = await ref
      .read(playerProvider)
      .autoBounds
      ?.call(track)
      .timeout(const Duration(seconds: 4))
      .catchError((Object _) => null);
  final intro = bounds?.start;
  if (intro == null || intro < const Duration(seconds: 2)) return l;
  final match = ref.read(sourcesProvider)[SourceKind.match];
  final played = track.source == SourceKind.match && match is MatchSource
      ? match.matched(track)?.duration
      : track.duration;
  final recorded = l.length;
  // Only when what plays really is longer by about that much.
  if (played != null && recorded != null && played - recorded < intro * 0.5) {
    return l;
  }
  return l.withShift(intro);
});
