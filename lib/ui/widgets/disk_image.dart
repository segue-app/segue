import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A network image that is kept on disk once fetched.
///
/// Flutter's own network images live in memory only: every launch
/// downloaded every cover again (data, battery, a slow first screen).
/// Covers never change under the same address, so the file is used as is;
/// the folder is trimmed to [maxBytes] now and then, oldest files first.
@immutable
class DiskImage extends ImageProvider<DiskImage> {
  const DiskImage(this.url);

  final String url;

  static const maxBytes = 300 * 1024 * 1024;
  static final _http = http.Client();
  static Future<Directory>? _dir;

  static Future<Directory> _folder() => _dir ??= () async {
    final d = Directory(
      '${(await getApplicationCacheDirectory()).path}'
      '${Platform.pathSeparator}covers',
    );
    await d.create(recursive: true);
    // Housekeeping a while after start, off the first screen's back.
    Timer(const Duration(seconds: 40), () => unawaited(_trim(d)));
    return d;
  }();

  static Future<void> _trim(Directory d) async {
    try {
      final files = <(File, FileStat)>[];
      await for (final e in d.list()) {
        if (e is File) files.add((e, await e.stat()));
      }
      var total = files.fold(0, (n, f) => n + f.$2.size);
      if (total <= maxBytes) return;
      files.sort((a, b) => a.$2.accessed.compareTo(b.$2.accessed));
      for (final (f, st) in files) {
        if (total <= maxBytes * 0.8) break;
        await f.delete();
        total -= st.size;
      }
    } catch (_) {}
  }

  @override
  Future<DiskImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final name = sha1.convert(utf8.encode(url)).toString();
    final file = File(
      '${(await _folder()).path}${Platform.pathSeparator}$name',
    );
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }
      } catch (_) {
        // A broken file (a download cut short): fetch it again.
      }
      unawaited(file.delete().catchError((Object _) => file));
    }
    final res = await _http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw NetworkImageLoadException(
        statusCode: res.statusCode,
        uri: Uri.parse(url),
      );
    }
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(res.bodyBytes),
    );
    // Saved only once it decoded; written aside first so a half-written
    // file is never read.
    unawaited(
      () async {
        final tmp = File('${file.path}.part');
        await tmp.writeAsBytes(res.bodyBytes, flush: true);
        await tmp.rename(file.path);
      }().catchError((Object _) {}),
    );
    return codec;
  }

  @override
  bool operator ==(Object other) => other is DiskImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskImage("$url")';
}
