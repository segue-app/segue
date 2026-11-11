import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Serves HLS streams to libmpv from a loopback server.
///
/// FFmpeg's HLS demuxer opens a fresh TLS connection for the playlist and
/// for every segment, which costs ~2.5 s before the first sound. Here Dart
/// fetches the playlist and segments over one keep-alive connection, reads
/// a few segments ahead, and can [prefetch] the start of the next track so
/// switching to it begins almost at once.
class HlsProxy {
  HlsProxy._();
  static final instance = HlsProxy._();

  /// How many segments to keep loading ahead of the one being played.
  static const _ahead = 3;

  final _http = http.Client();
  HttpServer? _server;
  final _streams = <String, _Stream>{};
  final _order = <String>[];
  var _ids = 0;

  Future<int> _port() async {
    final s = _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen(_serve);
    return s.port;
  }

  /// A loopback URL for [playlist] that mpv plays like the original.
  Future<Uri> wrap(Uri playlist) async {
    final port = await _port();
    final s = _streamFor(playlist);
    await s.ready;
    return Uri.parse('http://127.0.0.1:$port/h/${s.id}/index.m3u8');
  }

  /// Loads the playlist and the first segments of [playlist] in the
  /// background, so a later [wrap] starts playing straight from memory.
  void prefetch(Uri playlist) {
    final s = _streamFor(playlist);
    s.ready.then((_) => s.readAhead(0)).ignore();
  }

  _Stream _streamFor(Uri playlist) {
    final key = playlist.toString();
    for (final s in _streams.values) {
      if (s.source == key && !s.failed) return s;
    }
    final s = _Stream('${++_ids}', key, _http);
    _streams[s.id] = s;
    _order.add(s.id);
    // Keep the current track, the prefetched next one and a little history.
    while (_order.length > 4) {
      _streams.remove(_order.removeAt(0));
    }
    return s;
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      final parts = req.uri.pathSegments; // h/<id>/index.m3u8 | h/<id>/s/<n>
      final s = parts.length >= 3 ? _streams[parts[1]] : null;
      if (s == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (parts[2] == 'index.m3u8') {
        await s.ready;
        res.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        res.write(s.playlist);
        return;
      }
      final n = parts.length == 4 ? int.tryParse(parts[3]) : null;
      if (parts[2] != 's' || n == null || n >= s.urls.length) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = await s.segment(n);
      s.readAhead(n + 1);
      res.headers.contentType = ContentType.binary;
      res.contentLength = bytes.length;
      res.add(bytes);
    } catch (e) {
      debugPrint('hls proxy ${req.uri.path}: $e');
      res.statusCode = HttpStatus.badGateway;
    } finally {
      await res.close().catchError((Object _) {});
    }
  }
}

class _Stream {
  _Stream(this.id, this.source, this._http) {
    ready = _load();
    // A failed load is not reused: the next wrap() starts over.
    ready.catchError((Object _) => failed = true).ignore();
  }

  bool failed = false;

  final String id;
  final String source;
  final http.Client _http;

  late final Future<void> ready;

  /// The rewritten playlist pointing at the proxy.
  late String playlist;

  /// Original URLs, indexed like the proxy's `s/<n>` paths (the init
  /// segment of fMP4 streams included).
  final urls = <Uri>[];
  final _segments = <int, Future<Uint8List>>{};

  Future<void> _load() async {
    final base = Uri.parse(source);
    final res = await _http.get(base).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw StateError('playlist ${res.statusCode}');
    final out = StringBuffer();
    String local(String uri) {
      urls.add(base.resolve(uri));
      return 's/${urls.length - 1}';
    }

    for (final raw in res.body.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        // URI="..." in EXT-X-MAP (fMP4 init) and the like.
        out.writeln(
          line.replaceAllMapped(
            RegExp(r'URI="([^"]+)"'),
            (m) => 'URI="${local(m.group(1)!)}"',
          ),
        );
      } else {
        out.writeln(local(line));
      }
    }
    playlist = out.toString();
  }

  Future<Uint8List> segment(int n) {
    final hit = _segments[n];
    if (hit != null) return hit;
    final f = _fetch(urls[n]);
    _segments[n] = f;
    // A failed fetch must not stay cached: mpv will retry it.
    f.catchError((Object _) {
      _segments.remove(n);
      return Uint8List(0);
    }).ignore();
    // Forget what was played long ago; seeking back just fetches again.
    _segments.removeWhere((k, _) => k < n - 4);
    return f;
  }

  void readAhead(int from) {
    for (var n = from; n < from + HlsProxy._ahead && n < urls.length; n++) {
      segment(n).ignore();
    }
  }

  Future<Uint8List> _fetch(Uri url) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final res = await _http.get(url).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) return res.bodyBytes;
        throw StateError('segment ${res.statusCode}');
      } catch (e) {
        if (attempt >= 2) rethrow;
      }
    }
  }
}
