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
  final _tees = <String, _Tee>{};
  var _next = 0;
  static const _chunk = 512 * 1024;

  /// Where the bytes the player reads are also written, so a song that
  /// played through is on disk already (the offline cache takes it
  /// instead of downloading it again). Null: nothing is kept.
  Directory? teeDir;

  /// A local URL for [url] of [length] bytes. [mime] names the kept file.
  Future<Uri> wrap(Uri url, int length, {String? mime}) async {
    final server = _server ??= await _start();
    final id = '${_next++}';
    _files[id] = (url, length);
    // A long session wrapped hundreds of songs: old links are long dead.
    while (_files.length > 32) {
      _files.remove(_files.keys.first);
    }
    final dir = teeDir;
    if (dir != null) {
      try {
        dir.createSync(recursive: true);
        _tees[id] = _Tee(
          File('${dir.path}${Platform.pathSeparator}tee_$id.${_ext(mime)}'),
          length,
        );
      } catch (_) {}
      // A few recent songs only: the rest are given up and deleted.
      while (_tees.length > 4) {
        _tees.remove(_tees.keys.first)?.discard();
      }
    }
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
        _tees[req.uri.pathSegments.last]?.write(pos, bytes);
        res.add(bytes);
        await res.flush();
        pos += bytes.length;
      }
    } catch (_) {
      // Player closed the connection (seek): nothing to do.
    }
    await res.close();
  }

  /// The whole file behind [local] (a URL from [wrap]) once every byte of
  /// it went through, or null if it won't be (unknown URL, given up).
  Future<File?> kept(Uri local, {Duration wait = const Duration(minutes: 2)}) {
    if (local.host != '127.0.0.1' || local.port != _server?.port) {
      return Future.value(null);
    }
    final tee = _tees[local.pathSegments.last];
    if (tee == null) return Future.value(null);
    return tee.done.future.timeout(wait, onTimeout: () => null);
  }

  static String _ext(String? mime) {
    final m = mime ?? '';
    if (m.contains('webm') || m.contains('opus')) return 'webm';
    if (m.contains('mpeg') || m.contains('mp3')) return 'mp3';
    return 'm4a';
  }
}

/// One file being filled in as the player reads it (in any order: seeks
/// jump around), complete when every byte arrived.
class _Tee {
  _Tee(this.file, this.length);

  final File file;
  final int length;
  final done = Completer<File?>();

  RandomAccessFile? _raf;
  final _have = <(int, int)>[]; // merged [from, to) ranges
  var _writing = Future<void>.value();
  var _failed = false;

  void write(int pos, List<int> bytes) {
    if (_failed || done.isCompleted) return;
    _writing = _writing.then((_) async {
      try {
        final raf = _raf ??= await file.open(mode: FileMode.write);
        await raf.setPosition(pos);
        await raf.writeFrom(bytes);
        _add(pos, pos + bytes.length);
        if (_have.length == 1 && _have[0].$1 == 0 && _have[0].$2 >= length) {
          await raf.close();
          _raf = null;
          done.complete(file);
        }
      } catch (_) {
        discard();
      }
    });
  }

  void _add(int from, int to) {
    _have.add((from, to));
    _have.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in _have) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      } else {
        merged.add(r);
      }
    }
    _have
      ..clear()
      ..addAll(merged);
  }

  /// Given up: the file goes, unless someone took it away already (the
  /// cache moves a finished one into its own folder).
  void discard() {
    _failed = true;
    if (!done.isCompleted) done.complete(null);
    unawaited(() async {
      await _writing.catchError((Object _) {});
      try {
        await _raf?.close();
      } catch (_) {}
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }());
  }
}
