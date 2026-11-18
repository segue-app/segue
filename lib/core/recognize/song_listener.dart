import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../library/library.dart';
import '../library/library_store.dart';
import 'shazam.dart';
import 'shazam_signature.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Why listening stopped without a song.
class ListenException implements Exception {
  ListenException(this.message, {this.permission = false});

  final String message;

  /// The microphone isn't allowed: the user has to change that.
  final bool permission;

  @override
  String toString() => message;
}

/// "Что играет?": listens through the microphone and asks Shazam, first
/// after a few seconds and again with more, so a clear song is named
/// quickly and a hard one still gets the full 12 seconds.
class SongListener {
  SongListener(this._library, {Shazam? shazam}) : _shazam = shazam ?? Shazam();

  final LibraryStore _library;
  final Shazam _shazam;

  static const _rate = ShazamSignature.sampleRate;

  /// When to ask: seconds of sound heard by then.
  static const tries = [4, 8, 12];

  AudioRecorder? _rec;
  bool _cancelled = false;

  /// Listens until the song is known or 12 seconds have gone by. [heard]
  /// reports seconds of sound so far. Null: Shazam doesn't know it.
  Future<RecognizedSong?> listen({void Function(double seconds)? heard}) async {
    _cancelled = false;
    final rec = _rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        throw ListenException(
          'Нет доступа к микрофону. Разреши его Segue в настройках системы'.tr,
          permission: true,
        );
      }
      final stream = await rec.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
          // What's in the room, not a voice call: no cleanup that would
          // take the music for noise.
          echoCancel: false,
          noiseSuppress: false,
          autoGain: true,
        ),
      );
      final bytes = BytesBuilder(copy: false);
      var next = 0;
      final done = Completer<RecognizedSong?>();
      Future<void>? asking;

      late final StreamSubscription<Uint8List> sub;
      sub = stream.listen(
        (chunk) {
          bytes.add(chunk);
          final seconds = bytes.length / 2 / _rate;
          heard?.call(seconds);
          if (next >= tries.length ||
              seconds < tries[next] ||
              asking != null ||
              done.isCompleted) {
            return;
          }
          final last = next == tries.length - 1;
          next++;
          final pcm = _samples(bytes.toBytes());
          asking = _shazam
              .recognize(pcm)
              .then((song) {
                if (done.isCompleted) return;
                if (song != null || last) done.complete(song);
              })
              .catchError((Object e) {
                if (!done.isCompleted && last) done.completeError(e);
              })
              .whenComplete(() => asking = null);
        },
        onError: (Object e) {
          if (!done.isCompleted) {
            done.completeError(ListenException('Микрофон не отвечает'.tr));
          }
        },
        // Stopped (cancelled): nothing more is coming.
        onDone: () {
          if (!done.isCompleted && asking == null) done.complete(null);
        },
      );
      // A last try may still be on its way when time is up.
      final limit = Timer(Duration(seconds: tries.last + 15), () {
        if (!done.isCompleted) done.complete(null);
      });
      try {
        return await done.future;
      } finally {
        limit.cancel();
        await sub.cancel();
      }
    } finally {
      _rec = null;
      await rec.stop().catchError((Object _) => null);
      await rec.dispose().catchError((Object _) {});
    }
  }

  /// Stops listening early (the sheet was closed).
  Future<void> cancel() async {
    _cancelled = true;
    await _rec?.stop().catchError((Object _) => null);
  }

  bool get cancelled => _cancelled;

  /// The last 12 seconds as samples.
  static Int16List _samples(Uint8List b) {
    final count = b.length ~/ 2;
    final keep = count.clamp(0, tries.last * _rate);
    final view = ByteData.sublistView(b);
    final out = Int16List(keep);
    final from = count - keep;
    for (var i = 0; i < keep; i++) {
      out[i] = view.getInt16((from + i) * 2, Endian.little);
    }
    return out;
  }

  // --- what was recognised, newest first (this device only) ---------------

  static const _key = 'recognized';

  List<({RecognizedSong song, DateTime at})> history() {
    try {
      final list = jsonDecode(_library.getMeta(_key) ?? '[]') as List;
      return [
        for (final e in list.cast<Map>())
          if (RecognizedSong.fromJson(e) case final song?)
            (
              song: song,
              at: DateTime.fromMillisecondsSinceEpoch(e['at'] as int? ?? 0),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  void remember(RecognizedSong song) {
    final same = '${song.artist}|${song.title}'.toLowerCase();
    final list = [
      {...song.toJson(), 'at': DateTime.now().millisecondsSinceEpoch},
      for (final e in history())
        if ('${e.song.artist}|${e.song.title}'.toLowerCase() != same)
          {...e.song.toJson(), 'at': e.at.millisecondsSinceEpoch},
    ];
    _library.setMeta(_key, jsonEncode(list.take(100).toList()));
  }
}

final songListenerProvider = Provider<SongListener>(
  (ref) => SongListener(ref.watch(libraryProvider)),
);
