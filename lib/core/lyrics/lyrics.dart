import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';

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
  Lyrics({required this.lines, required this.synced});

  /// For plain (unsynced) lyrics every line has time zero.
  final List<LyricLine> lines;
  final bool synced;

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

  Future<Lyrics?> fetch(Track track) async {
    if (_cache.containsKey(track.key)) return _cache[track.key];
    final q = cleanQuery(track);
    final res = await _http
        .get(
          Uri.https('lrclib.net', '/api/search', {'q': q}),
          headers: {'User-Agent': 'Segue (https://github.com/segue-app/segue)'},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final items = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();

    // Prefer synced lyrics whose length matches the track.
    final dur = track.duration?.inSeconds;
    double score(Map<String, dynamic> it) {
      var s = it['syncedLyrics'] != null ? 0.0 : 30.0;
      final d = (it['duration'] as num?)?.toDouble();
      if (dur != null && d != null) s += (d - dur).abs();
      if (it['instrumental'] == true) s += 1000;
      return s;
    }

    final usable =
        items
            .where(
              (it) => it['syncedLyrics'] != null || it['plainLyrics'] != null,
            )
            .toList()
          ..sort((a, b) => score(a).compareTo(score(b)));
    Lyrics? result;
    if (usable.isNotEmpty && score(usable.first) < 60) {
      final best = usable.first;
      result = best['syncedLyrics'] != null
          ? Lyrics.parseLrc(best['syncedLyrics'] as String)
          : Lyrics.plain(best['plainLyrics'] as String);
    }
    _cache[track.key] = result;
    return result;
  }
}

final lyricsServiceProvider = Provider<LyricsService>((ref) => LyricsService());

final lyricsProvider = FutureProvider.family<Lyrics?, Track>(
  (ref, track) => ref.read(lyricsServiceProvider).fetch(track),
);
