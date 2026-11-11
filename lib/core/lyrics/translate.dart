import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'lyrics.dart';

/// Line-by-line lyrics translation through Google Translate's free web
/// endpoint (no key). Only the lyrics text is sent.
class LyricsTranslator {
  LyricsTranslator({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Translations of [lines] into [to] (same length), or null when the text
  /// is already in that language or the service did not answer usefully.
  Future<List<String>?> translate(List<String> lines, String to) async {
    if (lines.every((l) => l.trim().isEmpty)) return null;
    final out = <String>[];
    String? detected;
    // The endpoint takes a few thousand characters per request.
    for (final chunk in _chunks(lines, 1800)) {
      final res = await _http
          .post(
            Uri.parse(
              'https://translate.googleapis.com/translate_a/single'
              '?client=gtx&sl=auto&tl=$to&dt=t',
            ),
            body: {'q': chunk.join('\n')},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      detected ??= data.length > 2 ? data[2] as String? : null;
      final text = [
        for (final seg in (data[0] as List? ?? const []))
          (seg as List)[0] as String? ?? '',
      ].join();
      final got = text.split('\n');
      // Lines must still pair up one to one; otherwise it's unusable.
      if (got.length != chunk.length) return null;
      out.addAll(got.map((l) => l.trim()));
    }
    if (detected == to) return null;
    return out;
  }

  static Iterable<List<String>> _chunks(List<String> lines, int max) sync* {
    var cur = <String>[], size = 0;
    for (final l in lines) {
      if (size + l.length > max && cur.isNotEmpty) {
        yield cur;
        cur = [];
        size = 0;
      }
      cur.add(l);
      size += l.length + 1;
    }
    if (cur.isNotEmpty) yield cur;
  }
}

final lyricsTranslatorProvider = Provider((ref) => LyricsTranslator());

/// Translation of a track's lyrics into the device language, one string per
/// lyrics line; null when there is nothing to translate.
final lyricsTranslationProvider = FutureProvider.family<List<String>?, Track>((
  ref,
  track,
) async {
  final lyrics = await ref.watch(lyricsProvider(track).future);
  if (lyrics == null) return null;
  final to = PlatformDispatcher.instance.locale.languageCode;
  try {
    return await ref.read(lyricsTranslatorProvider).translate([
      for (final l in lyrics.lines) l.text,
    ], to);
  } catch (_) {
    return null;
  }
});
