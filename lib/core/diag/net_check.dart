import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import '../sources/music_source.dart';

/// One service the app talks to, and whether it answers from here.
class NetResult {
  const NetResult(this.name, {required this.ok, this.ms, this.error});

  final String name;
  final bool ok;
  final int? ms;

  /// Why it failed, short (an HTTP status, a timeout, a refused connection).
  final String? error;

  @override
  String toString() =>
      '${ok ? 'OK ' : 'ERR'} $name${ms == null ? '' : ' ${ms}ms'}'
      '${error == null ? '' : ' — $error'}';
}

/// Checks, from this device and its network, every service Segue needs.
/// Some are blocked in some countries (YouTube in Russia, Yandex Music
/// outside Russia and Belarus): this shows which, so the user knows what
/// a VPN would fix, and can send the report.
class NetCheck {
  NetCheck({required this.sources, http.Client? client})
    : _http = client ?? http.Client();

  final Map<SourceKind, MusicSource> sources;
  final http.Client _http;

  static const _timeout = Duration(seconds: 12);

  /// Names of the checks, in the order [run] reports them.
  static const names = [
    'YouTube: поиск',
    'YouTube: звук',
    'SoundCloud',
    'Яндекс Музыка',
    'Spotify',
    'Тексты песен',
    'Обновления',
  ];

  /// Runs every check at once; [onResult] gets each as it finishes.
  Future<List<NetResult>> run({void Function(NetResult r)? onResult}) async {
    final checks = <Future<NetResult>>[
      _time(names[0], _youtubeSearch),
      _time(names[1], _youtubeAudio),
      _time(names[2], _soundcloud),
      _time(names[3], () => _get('https://api.music.yandex.net/albums/1')),
      _time(
        names[4],
        () =>
            _get('https://open.spotify.com/embed/album/4aawyAB9vmqN3uQ7FjRGTy'),
      ),
      _time(names[5], () => _get('https://lrclib.net/api/search?q=hello')),
      _time(
        names[6],
        () => _get(
          'https://api.github.com/repos/segue-app/segue/releases/latest',
        ),
      ),
    ];
    for (final c in checks) {
      unawaited(c.then((r) => onResult?.call(r)));
    }
    return Future.wait(checks);
  }

  Future<NetResult> _time(String name, Future<void> Function() check) async {
    final sw = Stopwatch()..start();
    try {
      await check().timeout(_timeout);
      return NetResult(name, ok: true, ms: sw.elapsedMilliseconds);
    } on TimeoutException {
      return NetResult(name, ok: false, error: 'нет ответа за 12 с');
    } on StatusError catch (e) {
      return NetResult(name, ok: false, error: e.toString());
    } on SocketException catch (e) {
      return NetResult(name, ok: false, error: e.osError?.message ?? e.message);
    } on HandshakeException {
      return NetResult(
        name,
        ok: false,
        error: 'TLS оборван (похоже на блокировку)',
      );
    } catch (e) {
      final s = '$e';
      return NetResult(
        name,
        ok: false,
        error: s.length > 120 ? '${s.substring(0, 120)}…' : s,
      );
    }
  }

  Future<void> _get(String url, {Map<String, String>? headers}) async {
    final res = await _http.get(Uri.parse(url), headers: headers);
    if (res.statusCode >= 400) throw StatusError(res.statusCode);
  }

  Future<void> _youtubeSearch() async {
    final yt = sources[SourceKind.youtube];
    if (yt == null) throw StateError('нет источника');
    final r = await yt.search('Daft Punk One More Time', limit: 1);
    if (r.isEmpty) throw StateError('пустой ответ');
  }

  /// The audio itself comes from another host (googlevideo.com), which is
  /// what some networks slow down or cut.
  Future<void> _youtubeAudio() async {
    final yt = sources[SourceKind.youtube];
    if (yt == null) throw StateError('нет источника');
    final info = await yt.resolveStream(
      const Track(
        id: 'FGBhQbmPwH8',
        source: SourceKind.youtube,
        title: 'One More Time',
        artist: 'Daft Punk',
      ),
    );
    if (info.hls) {
      await _get(info.url.toString());
      return;
    }
    final res = await _http.get(info.url, headers: {'Range': 'bytes=0-65535'});
    if (res.statusCode >= 400) throw StatusError(res.statusCode);
    if (res.bodyBytes.length < 1024) throw StateError('звук не пришёл');
  }

  Future<void> _soundcloud() async {
    final sc = sources[SourceKind.soundcloud];
    if (sc == null) throw StateError('нет источника');
    final r = await sc.search('Daft Punk', limit: 1);
    if (r.isEmpty) throw StateError('пустой ответ');
  }
}

/// A service answered with an error status.
class StatusError implements Exception {
  const StatusError(this.code);

  final int code;

  @override
  String toString() => switch (code) {
    451 => 'ошибка 451: недоступно в этой стране',
    403 => 'ошибка 403: доступ закрыт',
    429 => 'ошибка 429: слишком много запросов с этого адреса',
    _ => 'ошибка $code',
  };
}
