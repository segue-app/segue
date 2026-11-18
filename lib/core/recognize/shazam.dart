import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'shazam_signature.dart';

import 'package:segue/core/l10n/l10n.dart';

/// A song Shazam recognised.
class RecognizedSong {
  const RecognizedSong({
    required this.title,
    required this.artist,
    this.coverUrl,
    this.album,
    this.year,
    this.shazamUrl,
  });

  final String title;
  final String artist;
  final String? coverUrl;
  final String? album;
  final String? year;
  final String? shazamUrl;

  /// To play: found on YouTube by title and artist, like an import.
  Track get track => Track(
    id: '$artist — $title',
    source: SourceKind.match,
    title: title,
    artist: artist,
    artworkUrl: coverUrl,
  );

  Map<String, dynamic> toJson() => {
    't': title,
    'a': artist,
    if (coverUrl != null) 'c': coverUrl,
    if (album != null) 'al': album,
    if (year != null) 'y': year,
    if (shazamUrl != null) 'u': shazamUrl,
  };

  static RecognizedSong? fromJson(Map j) {
    final t = j['t'], a = j['a'];
    if (t is! String || a is! String) return null;
    return RecognizedSong(
      title: t,
      artist: a,
      coverUrl: j['c'] as String?,
      album: j['al'] as String?,
      year: j['y'] as String?,
      shazamUrl: j['u'] as String?,
    );
  }
}

class RecognizeException implements Exception {
  RecognizeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Asks Shazam what a fingerprint is, the way SongRec does (Shazam has no
/// public API; this is what its Android app sends). Only the fingerprint
/// travels, and no account or id of the user: the request ids are random
/// each time.
class Shazam {
  Shazam({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _rnd = Random();

  static const _agents = [
    'Dalvik/2.1.0 (Linux; U; Android 10; SM-G973F Build/QP1A.190711.020)',
    'Dalvik/2.1.0 (Linux; U; Android 11; Pixel 4a Build/RQ3A.210805.001.A1)',
    'Dalvik/2.1.0 (Linux; U; Android 12; SM-A525F Build/SP1A.210812.016)',
    'Dalvik/2.1.0 (Linux; U; Android 13; 2201117TY Build/TKQ1.221114.001)',
  ];

  String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// The song in [samples] (16 kHz mono, 16-bit), or null when Shazam
  /// doesn't know it.
  Future<RecognizedSong?> recognize(Int16List samples) =>
      recognizeSignature(ShazamSignature.of(samples));

  Future<RecognizedSong?> recognizeSignature(ShazamSignature sig) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final url =
        Uri.parse(
          'https://amp.shazam.com/discovery/v5/en/US/android/-/tag/'
          '${_uuid().toUpperCase()}/${_uuid()}',
        ).replace(
          queryParameters: {
            'sync': 'true',
            'webv3': 'true',
            'sampling': 'true',
            'connected': '',
            'shazamapiversion': 'v3',
            'sharehub': 'true',
            'video': 'v3',
          },
        );
    final http.Response res;
    try {
      res = await _http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _agents[_rnd.nextInt(_agents.length)],
              'Content-Language': 'en_US',
            },
            body: jsonEncode({
              // Somewhere neutral, as SongRec does: not the user's place.
              'geolocation': {'altitude': 300, 'latitude': 45, 'longitude': 2},
              'signature': {
                'samplems': sig.length.inMilliseconds,
                'timestamp': now,
                'uri': sig.uri,
              },
              'timestamp': now,
              'timezone': 'Europe/Paris',
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw RecognizeException('Нет связи с Shazam'.tr);
    }
    if (res.statusCode == 429) {
      throw RecognizeException(
        'Shazam просит подождать. Попробуй через минуту'.tr,
      );
    }
    if (res.statusCode != 200) {
      throw RecognizeException(
        'Shazam ответил ошибкой {0}'.trArgs([res.statusCode]),
      );
    }
    return parse(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  /// The song in Shazam's answer (null: no match).
  static RecognizedSong? parse(Object? body) {
    if (body is! Map) return null;
    final matches = body['matches'];
    final track = body['track'];
    if (matches is! List || matches.isEmpty || track is! Map) return null;
    final title = track['title'], artist = track['subtitle'];
    if (title is! String || artist is! String) return null;
    final images = track['images'] as Map?;
    String? album, year;
    for (final s in (track['sections'] as List? ?? const [])) {
      if (s is! Map || s['type'] != 'SONG') continue;
      for (final m in (s['metadata'] as List? ?? const [])) {
        if (m is! Map) continue;
        if (m['title'] == 'Album') album = m['text'] as String?;
        if (m['title'] == 'Released') year = m['text'] as String?;
      }
    }
    return RecognizedSong(
      title: title,
      artist: artist,
      coverUrl: (images?['coverarthq'] ?? images?['coverart']) as String?,
      album: album,
      year: year,
      shazamUrl: track['url'] as String?,
    );
  }
}
