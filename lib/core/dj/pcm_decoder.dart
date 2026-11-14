import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

/// Turns a stretch of a song into raw samples for analysis: a silent
/// libmpv of its own writes mono 16-bit PCM to a file, as fast as it can
/// decode (not in real time), and the file is read back.
class PcmDecoder {
  PcmDecoder({Directory? temp})
    : _temp = temp; // ignore: prefer_initializing_formals

  static const sampleRate = 11025;

  final Directory? _temp;
  Player? _player;
  Future<void> _queue = Future.value();

  /// Samples of [uri] from [start] for [length]. One at a time.
  Future<Int16List?> decode(Uri uri, {Duration? start, Duration? length}) {
    final run = _queue.then((_) => _decode(uri, start, length));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Int16List?> _decode(Uri uri, Duration? start, Duration? length) async {
    final dir = _temp ?? Directory.systemTemp;
    final file = File(
      '${dir.path}${Platform.pathSeparator}segue_pcm_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    final p = _player ??= Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.error,
        title: 'Segue analysis',
      ),
    );
    final native = p.platform;
    if (native is! NativePlayer) return null;
    try {
      for (final (k, v) in [
        ('vid', 'no'),
        ('ao', 'pcm'),
        ('ao-pcm-file', file.path),
        ('ao-pcm-waveheader', 'no'),
        ('audio-format', 's16'),
        ('audio-channels', 'mono'),
        ('audio-samplerate', '$sampleRate'),
        ('untimed', 'yes'),
        ('volume', '100'),
        ('af', ''),
        ('cache', 'yes'),
        ('end', 'none'),
        ('length', length == null ? 'none' : '${length.inMilliseconds / 1000}'),
      ]) {
        await native.setProperty(k, v);
      }
      final done = p.stream.completed.firstWhere((c) => c);
      await p.open(Media(uri.toString(), start: start), play: true);
      await done.timeout(const Duration(seconds: 40));
      await p.stop();
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return bytes.buffer.asInt16List(0, bytes.lengthInBytes ~/ 2);
    } catch (_) {
      await p.stop().catchError((Object _) {});
      return null;
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
  }
}
