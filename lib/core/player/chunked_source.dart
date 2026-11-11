import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Local HTTP proxy that serves a remote file in small range requests.
///
/// Players ask for `bytes=0-` (the whole file); YouTube answers such
/// requests with 403 and only serves ranges up to ~1 MB. The player reads
/// from this proxy instead, which fetches 512 KB pieces behind it.
class ChunkProxy {
  ChunkProxy._();
  static final instance = ChunkProxy._();

  HttpServer? _server;
  final _client = http.Client();
  final _files = <String, (Uri, int)>{};
  var _next = 0;
  static const _chunk = 512 * 1024;

  /// A local URL for [url] of [length] bytes.
  Future<Uri> wrap(Uri url, int length) async {
    final server = _server ??= await _start();
    final id = '${_next++}';
    _files[id] = (url, length);
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/f/$id',
    );
  }

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_serve, onError: (_) {});
    return s;
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    final entry = _files[req.uri.pathSegments.last];
    if (entry == null) {
      res.statusCode = 404;
      return res.close();
    }
    final (url, length) = entry;
    var from = 0, to = length - 1;
    final range = RegExp(r'bytes=(\d*)-(\d*)')
        .firstMatch(req.headers.value('range') ?? '');
    if (range != null) {
      if (range[1]!.isNotEmpty) from = int.parse(range[1]!);
      if (range[2]!.isNotEmpty) {
        to = int.parse(range[2]!).clamp(from, length - 1);
      }
      res.statusCode = HttpStatus.partialContent;
      res.headers.set('Content-Range', 'bytes $from-$to/$length');
    }
    res.headers
      ..set('Accept-Ranges', 'bytes')
      ..contentLength = to - from + 1
      ..contentType = ContentType('audio', 'mp4');
    if (req.method == 'HEAD') return res.close();
    try {
      var pos = from;
      while (pos <= to) {
        final last = (pos + _chunk - 1).clamp(0, to);
        List<int>? bytes;
        for (var attempt = 0; attempt < 3 && bytes == null; attempt++) {
          try {
            final r = await _client
                .get(url, headers: {'Range': 'bytes=$pos-$last'})
                .timeout(const Duration(seconds: 15));
            if (r.statusCode == 200 || r.statusCode == 206) bytes = r.bodyBytes;
          } catch (_) {}
        }
        if (bytes == null || bytes.isEmpty) break;
        res.add(bytes);
        await res.flush();
        pos += bytes.length;
      }
    } catch (_) {
      // Player closed the connection (seek): nothing to do.
    }
    await res.close();
  }
}
