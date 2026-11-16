import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Free public YouTube mirrors (Invidious and Piped): a way around when
/// YouTube itself is blocked or throttled on this network.
///
/// Volunteers run them, so they come and go. The list is fetched fresh,
/// mirrors that answered are tried first, and every request is short.
class YtMirrors {
  YtMirrors({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// Piped has no machine-readable list, so these are its long-running
  /// public API hosts; Invidious hosts come from its own directory.
  static const _piped = [
    'https://api.piped.private.coffee',
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.leptons.xyz',
    'https://pipedapi.drgns.space',
    'https://pipedapi.ducks.party',
    'https://pipedapi.reallyaweso.me',
    'https://api.piped.yt',
  ];

  static const _timeout = Duration(seconds: 8);

  List<_Mirror>? _list;
  DateTime _listAt = DateTime(0);

  /// The mirror that last answered, tried first next time.
  _Mirror? _good;

  Future<List<_Mirror>> _mirrors() async {
    if (_list != null &&
        DateTime.now().difference(_listAt) < const Duration(hours: 6)) {
      return _list!;
    }
    final out = <_Mirror>[for (final p in _piped) _Mirror(p, piped: true)];
    try {
      final res = await _http
          .get(
            Uri.parse(
              'https://api.invidious.io/instances.json?sort_by=type,users',
            ),
          )
          .timeout(_timeout);
      for (final e in jsonDecode(res.body) as List) {
        final info = (e as List)[1] as Map;
        if (info['type'] == 'https' && info['api'] == true) {
          out.insert(0, _Mirror('${info['uri']}', piped: false));
        }
      }
    } catch (_) {}
    _listAt = DateTime.now();
    return _list = out;
  }

  /// Every mirror at once; the first good answer wins.
  Future<T> _first<T>(Future<T?> Function(_Mirror m) ask) async {
    final all = await _mirrors();
    final order = [?_good, ...all.where((m) => m != _good)];
    final done = Completer<T>();
    var left = order.length;
    for (final m in order) {
      ask(m)
          .timeout(_timeout)
          .then((v) {
            if (v != null && !done.isCompleted) {
              _good = m;
              done.complete(v);
            }
          }, onError: (Object _) {})
          .whenComplete(() {
            if (--left == 0 && !done.isCompleted) {
              done.completeError(StateError('no mirror answered'));
            }
          });
    }
    return done.future.timeout(const Duration(seconds: 15));
  }

  Future<Object?> _json(Uri uri) async {
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body);
  }

  /// Videos for [query]: id, title, channel, length.
  Future<List<MirrorVideo>> search(String query) => _first((m) async {
    if (m.piped) {
      final j = await _json(
        Uri.parse('${m.base}/search')
            .replace(queryParameters: {'q': query, 'filter': 'videos'}),
      );
      final items = (j as Map?)?['items'] as List? ?? const [];
      final out = [
        for (final i in items.cast<Map>())
          if (i['type'] == 'stream' && '${i['url']}'.contains('v='))
            MirrorVideo(
              id: '${i['url']}'.split('v=').last,
              title: '${i['title']}',
              author: '${i['uploaderName'] ?? ''}',
              seconds: (i['duration'] as num?)?.toInt() ?? 0,
              verified: i['uploaderVerified'] == true,
            ),
      ];
      return out.isEmpty ? null : out;
    }
    final j = await _json(
      Uri.parse('${m.base}/api/v1/search')
          .replace(queryParameters: {'q': query, 'type': 'video'}),
    );
    final out = [
      for (final i in (j as List? ?? const []).cast<Map>())
        if (i['type'] == 'video')
          MirrorVideo(
            id: '${i['videoId']}',
            title: '${i['title']}',
            author: '${i['author'] ?? ''}',
            seconds: (i['lengthSeconds'] as num?)?.toInt() ?? 0,
            verified: i['authorVerified'] == true,
          ),
    ];
    return out.isEmpty ? null : out;
  });

  /// Audio files of a video, best first, as the mirrors hand them out
  /// (Invidious through itself, so they work where googlevideo doesn't).
  /// [check] says whether a file really plays to the end.
  Future<MirrorAudio> audio(
    String id,
    Future<bool> Function(MirrorAudio a) check,
  ) => _first((m) async {
    final List<MirrorAudio> found;
    if (m.piped) {
      final j = await _json(Uri.parse('${m.base}/streams/$id')) as Map?;
      found = [
        for (final s in (j?['audioStreams'] as List? ?? const []).cast<Map>())
          if (s['url'] != null)
            MirrorAudio(
              Uri.parse('${s['url']}'),
              mimeType: '${s['mimeType'] ?? 'audio/mp4'}',
              bitrate: (s['bitrate'] as num?)?.toInt() ?? 0,
              length: int.tryParse('${s['contentLength'] ?? ''}'),
            ),
      ];
    } else {
      final j = await _json(
        Uri.parse('${m.base}/api/v1/videos/$id?local=true'),
      ) as Map?;
      found = [
        for (final f
            in (j?['adaptiveFormats'] as List? ?? const []).cast<Map>())
          if ('${f['type']}'.startsWith('audio/') && f['url'] != null)
            MirrorAudio(
              _absolute(m.base, '${f['url']}'),
              mimeType: '${f['type']}'.split(';').first,
              bitrate: int.tryParse('${f['bitrate']}') ?? 0,
              length: int.tryParse('${f['clen'] ?? ''}'),
            ),
      ];
    }
    // AAC first: it plays on every platform.
    found.sort((a, b) {
      final am = a.mimeType.contains('mp4') ? 1 : 0;
      final bm = b.mimeType.contains('mp4') ? 1 : 0;
      return am != bm ? bm - am : b.bitrate - a.bitrate;
    });
    for (final a in found.take(2)) {
      if (await check(a)) return a;
    }
    debugPrint('mirror ${m.base}: no playable audio');
    return null;
  });

  static Uri _absolute(String base, String url) =>
      url.startsWith('/') ? Uri.parse('$base$url') : Uri.parse(url);
}

class _Mirror {
  const _Mirror(this.base, {required this.piped});

  final String base;
  final bool piped;

  @override
  bool operator ==(Object other) => other is _Mirror && other.base == base;

  @override
  int get hashCode => base.hashCode;
}

@immutable
class MirrorVideo {
  const MirrorVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.seconds,
    this.verified = false,
  });

  final String id, title, author;
  final int seconds;
  final bool verified;
}

@immutable
class MirrorAudio {
  const MirrorAudio(
    this.url, {
    required this.mimeType,
    required this.bitrate,
    this.length,
  });

  final Uri url;
  final String mimeType;
  final int bitrate;
  final int? length;
}
