import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../models/track.dart';
import '../sources/music_source.dart';
import 'audio_fx.dart';
import 'car_browser.dart';
import 'chunked_source.dart';
import 'hls_proxy.dart';

import 'package:segue/core/l10n/l10n.dart';

/// What other devices need from a player: hand playback over, and control
/// it remotely ("Spotify Connect").
abstract interface class PlaybackControl {
  Map<String, dynamic> snapshot();
  Future<void> restore(Map<String, dynamic> snapshot);
  Future<void> pause();
  Future<void> play();
  Future<void> seek(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> skipToQueueItem(int index);
  Future<void> setVolume(double volume);
  Future<void> addNext(Track track);

  /// Fires when what others see changes: track, play/pause, seek, volume,
  /// queue.
  Stream<void> get stateChanges;
}

/// Owns playback and the queue. Exposed to the OS through audio_service, so
/// lock-screen, notification, headset and media keys all control it.
///
/// Audio is played by libmpv (media_kit) on every platform, so the effects
/// (EQ, pitch, reverb…) are FFmpeg filters that work the same everywhere.
/// Stream URLs expire, so each track is resolved just before it plays.
class SegueAudioHandler extends BaseAudioHandler
    with SeekHandler
    implements PlaybackControl {
  SegueAudioHandler(this._sources)
    : _player = Player(
        configuration: const PlayerConfiguration(
          title: 'Segue',
          logLevel: MPVLogLevel.warn,
        ),
      ) {
    final s = _player.stream;
    // "Until the end of this track" must not slide into the queued next.
    sleepAfterTrack.addListener(() {
      if (sleepAfterTrack.value) _dropGapless();
    });
    s.playing.listen((p) {
      // Stopping the old song for the next one isn't a pause.
      if (_switching) return;
      if (_out == null) _playingCtl.add(p);
      _broadcastState();
      _changed();
    });
    s.buffering.listen((_) => _broadcastState());
    s.completed.listen((done) {
      // The end of a track, not the reset that comes with opening the next.
      if (done && !_loading) _trackEnded();
    });
    s.position.listen((pos) {
      // While the next track loads, this is still the old one's position:
      // it must not move the new track's progress, fades, mix or trim.
      if (_switching) return;
      // mpv reports dozens of times a second; the UI needs a few (a jump,
      // like a seek or a new track, goes through at once).
      final now = DateTime.now();
      if (_out == null &&
          (now.difference(_posSentAt) >= const Duration(milliseconds: 200) ||
              (pos - _posSent).abs() > const Duration(seconds: 1))) {
        _posSentAt = now;
        _posSent = pos;
        _positionCtl.add(pos);
      }
      _fadeAt(pos);
      _maybeMix(pos);
      _maybeQueueNext(pos);
      // A trimmed track ends where its trim says.
      final end = _trimEnd;
      if (end != null &&
          pos >= end &&
          !_loading &&
          !_endedByTrim &&
          // A mix being prepared takes over in a moment; the song plays
          // on into its outro meanwhile instead of stopping.
          !_mixStarting) {
        _endedByTrim = true;
        _trackEnded();
      }
    });
    // The next song, queued in mpv itself, has started: no gap at all.
    s.playlist.listen((pl) {
      final g = _gapless;
      if (g != null && pl.index == 1 && pl.medias.length >= 2) {
        _advanceGapless(g);
      }
    });
    s.duration.listen((d) {
      // Sources that don't know the length: take the player's.
      final item = mediaItem.value;
      if (d > Duration.zero && item != null && item.duration == null) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
    unawaited(_configureMpv());
    s.error.listen((e) => debugPrint('mpv error: $e'));
    s.log.listen(
      (l) => debugPrint('mpv ${l.level}: ${l.prefix}: ${l.text.trim()}'),
    );
  }

  void _trackEnded() {
    _leaving(skipped: false);
    // A trimmed end with the next song queued: mpv moves on seamlessly.
    if (_gapless != null && !sleepAfterTrack.value) {
      unawaited(_player.next());
      return;
    }
    if (sleepAfterTrack.value) {
      // Sleep timer "until the end of the track": stay on it, paused.
      sleepAfterTrack.value = false;
      final start = _trimStart ?? Duration.zero;
      _player.pause().then((_) => _player.seek(start));
      return;
    }
    skipToNext();
  }

  /// Re-reads the current track's trim after it was edited.
  void refreshTrim() {
    final t = current;
    if (t == null) return;
    final trim = trimFor?.call(t);
    _trimStart = trim?.start;
    _trimEnd = trim?.end;
    _endedByTrim = false;
    if (_edgeGain != 1) {
      _edgeGain = 1;
      _applyVolume();
    }
  }

  /// Start and end a track is trimmed to (see TrimStore), if any.
  ({Duration? start, Duration? end})? Function(Track track)? trimFor;
  Duration? _trimStart;
  Duration? _trimEnd;
  bool _endedByTrim = false;

  final Map<SourceKind, MusicSource> _sources;
  final Player _player;

  final List<Track> _tracks = [];
  int _index = -1;
  int _loadToken = 0;

  /// The [_loadToken] whose track is actually open in the player.
  int _openedToken = 0;

  /// The next track is on its way (the old one is already stopped).
  bool get _switching => _openedToken != _loadToken;

  /// Playing as the user sees it: a track that's loading counts.
  bool get _localPlaying => _switching || _player.state.playing;

  Duration get _localPosition =>
      _switching ? (_trimStart ?? Duration.zero) : _player.state.position;
  bool _loading = false;
  AudioFx _fx = const AudioFx();

  List<Track> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  Track? get current =>
      _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;

  /// Position of what plays: this device's player, or the device this
  /// one is a remote for.
  Stream<Duration> get positionStream => _positionCtl.stream;
  final _positionCtl = StreamController<Duration>.broadcast();
  DateTime _posSentAt = DateTime(0);
  Duration _posSent = Duration.zero;

  /// Duration of the current track as published in [mediaItem], which
  /// prefers the source's exact value over the player's estimate.
  Stream<Duration?> get durationStream => mediaItem.map((m) => m?.duration);
  Stream<bool> get playingStream => _playingCtl.stream;
  final _playingCtl = StreamController<bool>.broadcast();

  /// Last error message (e.g. a stream that failed to resolve), or null.
  final errors = StreamController<String>.broadcast();

  /// Called once a track actually starts playing (for listening history).
  void Function(Track track)? onTrackStarted;

  /// Path of a downloaded copy, if any: played instead of streaming.
  String? Function(Track track)? localPathFor;

  /// Makes a seekable local copy of an HLS stream (see [_seekViaCopy]).
  Future<String> Function(StreamInfo info, Track track)? seekableCopy;

  /// Set while the current track is SoundCloud HLS played as a stream:
  /// seeking then switches to a stitched local copy.
  Future<String>? _copy;
  bool _onCopy = false;

  final _stateChanges = StreamController<void>.broadcast();
  @override
  Stream<void> get stateChanges => _stateChanges.stream;
  void _changed() => _stateChanges.add(null);

  /// Bumps on every queue change (order, length or current position).
  final queueVersion = ValueNotifier<int>(0);

  /// Endless mode ("Волна"): fetches more tracks as the queue runs out.
  Future<List<Track>> Function()? _refill;
  bool _refilling = false;

  /// Title of the running wave, null for an ordinary queue.
  final waveTitle = ValueNotifier<String?>(null);

  void _queueChanged() {
    _checkGapless();
    queue.add(_tracks.map(_toMediaItem).toList());
    queueVersion.value++;
    _changed();
  }

  /// A tap on a song in a list: the song that's playing pauses or goes on
  /// (like Yandex Music), any other starts from the beginning.
  Future<void> tapTrack(List<Track> list, int index, {String? context}) {
    final t = list[index];
    if (current?.key == t.key) {
      if (context != null) playContext.value = context;
      return isPlaying ? pause() : play();
    }
    return playList(list, index, context: context);
  }

  /// Where the queue came from ('liked', 'playlist:ID'…), so the screen
  /// can mark that playlist as the one playing.
  final playContext = ValueNotifier<String?>(null);

  /// Replaces the queue with [list] and starts playing [list[start]].
  Future<void> playList(
    List<Track> list,
    int start, {
    Duration? startAt,
    String? context,
  }) async {
    playContext.value = context;
    if (_out != null) {
      // Remote: it plays there.
      final from = start > 50 ? start - 50 : 0;
      await _out!.send('restore', {
        'snapshot': {
          'queue': [for (final t in list.skip(from).take(200)) t.toJson()],
          'index': start - from,
          'positionMs': startAt?.inMilliseconds ?? 0,
          'playing': true,
        },
      });
      return;
    }
    _refill = null;
    waveTitle.value = null;
    _tracks
      ..clear()
      ..addAll(list);
    _queueChanged();
    await _playIndex(start, startAt: startAt);
  }

  /// Plays [first] and keeps going with whatever [more] returns, forever.
  Future<void> playEndless(
    List<Track> first,
    Future<List<Track>> Function() more, {
    required String title,
  }) async {
    await playList(first, 0);
    _refill = more;
    waveTitle.value = title;
  }

  @override
  Future<void> addNext(Track t) async {
    if (_out != null) return _out!.send('add', {'track': t.toJson()});
    _tracks.insert(_index + 1, t);
    _queueChanged();
    _prefetchNext();
  }

  /// Corrected song data (e.g. an artist name fixed in the library):
  /// updates the queue and what's shown as playing.
  void updateTracks(Map<String, Track> byKey) {
    var changed = false;
    for (var i = 0; i < _tracks.length; i++) {
      final fixed = byKey[_tracks[i].key];
      if (fixed != null) {
        _tracks[i] = fixed;
        changed = true;
      }
    }
    if (!changed) return;
    _queueChanged();
    final t = current;
    if (t != null && byKey.containsKey(t.key)) {
      final item = mediaItem.value;
      mediaItem.add(
        _toMediaItem(t).copyWith(duration: item?.duration ?? t.duration),
      );
    }
  }

  /// Takes upcoming songs matching [test] out of the queue (the wave
  /// dropping an artist you just skipped twice).
  void removeUpcomingWhere(bool Function(Track t) test) {
    if (_out != null) return;
    final before = _tracks.length;
    final head = _tracks.sublist(0, _index + 1);
    final rest = _tracks.sublist(_index + 1)..removeWhere(test);
    if (head.length + rest.length == before) return;
    _tracks
      ..clear()
      ..addAll(head)
      ..addAll(rest);
    _queueChanged();
    _prefetchNext();
    unawaited(_maybeRefill());
  }

  /// Moves a queue item (drag & drop in the queue view). [to] is the final
  /// index, as ReorderableListView.onReorderItem reports it.
  void moveQueueItem(int from, int to) {
    if (from == to || from < 0 || from >= _tracks.length) return;
    final t = _tracks.removeAt(from);
    final dest = to.clamp(0, _tracks.length);
    _tracks.insert(dest, t);
    // Keep pointing at the track that is playing.
    if (from == _index) {
      _index = dest;
    } else if (from < _index && dest >= _index) {
      _index--;
    } else if (from > _index && dest <= _index) {
      _index++;
    }
    _queueChanged();
    _prefetchNext();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _tracks.length || index == _index) return;
    _tracks.removeAt(index);
    if (index < _index) _index--;
    _queueChanged();
    _prefetchNext();
  }

  Future<void> _maybeRefill() async {
    final refill = _refill;
    if (refill == null || _refilling || _index < _tracks.length - 3) return;
    _refilling = true;
    try {
      final have = {for (final t in _tracks) t.key};
      final more = (await refill()).where((t) => have.add(t.key)).toList();
      if (more.isNotEmpty && identical(refill, _refill)) {
        _tracks.addAll(more);
        _queueChanged();
        _prefetchNext();
      }
    } catch (e) {
      debugPrint('wave refill: $e');
    } finally {
      _refilling = false;
    }
  }

  Future<void> _playIndex(
    int i, {
    Duration? startAt,
    bool mixing = false,
  }) async {
    if (i < 0 || i >= _tracks.length) return;
    // A skip in the middle of a mix ends it at once.
    if (!mixing) _stopMix();
    // Opening replaces mpv's playlist, queued next song included.
    _gapless = null;
    _leaving(skipped: !mixing);
    _index = i;
    queueVersion.value++;
    unawaited(_maybeRefill());
    final track = _tracks[i];
    final trim = trimFor?.call(track);
    _trimStart = trim?.start;
    _trimEnd = trim?.end;
    _endedByTrim = false;
    startAt ??= _trimStart;
    final token = ++_loadToken;
    final sw = Stopwatch()..start();
    _loading = true;
    mediaItem.add(_toMediaItem(track));
    if (!mixing) {
      // Silence the old song at once (it would play on while the new one
      // resolves) and free the connection for the new one.
      unawaited(_player.stop());
      _positionCtl.add(startAt ?? Duration.zero);
    }
    _broadcastState();
    try {
      final local = localPathFor?.call(track);
      final isLocal = local != null && File(local).existsSync();
      StreamInfo info;
      String uri;
      for (var attempt = 0; ; attempt++) {
        try {
          info = isLocal
              ? StreamInfo(Uri.file(local), duration: track.duration)
              : attempt == 0
              ? await _resolve(track)
              : await _sources[track.source]!.resolveStream(track);
          if (token != _loadToken) return;
          uri = await _playableUri(info, proxy: attempt == 0);
          break;
        } catch (e) {
          // A prefetched link may have gone stale or the proxy may have
          // tripped: once more with a fresh link, played directly.
          if (isLocal || attempt > 0 || token != _loadToken) rethrow;
          debugPrint('play ${track.title}: $e — retrying fresh');
        }
      }
      // A newer request started while this one was resolving.
      if (token != _loadToken) return;
      // Where the music itself is (no spoken intro or skit at the end).
      final auto = skipIntros && autoBounds != null
          ? await autoBounds!(track)
                .timeout(const Duration(milliseconds: 700))
                .catchError((Object _) => null)
          : null;
      if (token != _loadToken) return;
      if (startAt == null && auto?.start != null) startAt = auto!.start;
      if (_trimEnd == null && auto?.end != null) _trimEnd = auto!.end;
      _currentUri = uri;
      _currentHls = info.hls;
      _normGain = _gainFor(track, info.loudnessDb);
      if (!mixing) await _applyVolume();
      // In a mix the new song starts silent; the mix fades it in.
      if (mixing) {
        _edgeGain = 0;
        await _applyVolume();
      }
      await _setTempo(mixing ? _mixTempo : 1);
      debugPrint('load ${track.title}: ready in ${sw.elapsedMilliseconds} ms');
      if (info.duration != null) {
        mediaItem.add(_toMediaItem(track).copyWith(duration: info.duration));
      }
      _onCopy = false;
      _copy = null;
      // libmpv can't seek in SoundCloud's fMP4 HLS (timestamps don't match
      // the playlist): build a whole-file copy in the background now.
      if (info.hls &&
          track.source != SourceKind.youtube &&
          seekableCopy != null) {
        _copy = seekableCopy!(info, track)..ignore();
      }
      // googlevideo refuses FFmpeg's keep-alive segment requests; fresh
      // connections avoid a failed attempt (and a log line) per segment.
      await _mpv('demuxer-lavf-o', info.hls ? 'http_persistent=0' : '');
      await _player.open(Media(uri, start: startAt), play: true);
      if (token == _loadToken) {
        _openedToken = token;
        if (_out == null) _playingCtl.add(_player.state.playing);
      }
      debugPrint('load ${track.title}: opened in ${sw.elapsedMilliseconds} ms');
      onTrackStarted?.call(track);
      _changed();
      _prefetchNext();
      if (mixing) _runMix();
    } catch (e) {
      if (token != _loadToken) return;
      _openedToken = token; // nothing is coming: report what really is
      _playingCtl.add(false);
      debugPrint('play ${track.title}: $e');
      errors.add('Не удалось воспроизвести «{0}»'.trArgs([track.title]));
      // Skip broken tracks instead of stopping the whole queue.
      if (_index < _tracks.length - 1) {
        _loading = false;
        await _playIndex(_index + 1);
      }
    } finally {
      if (token == _loadToken) {
        // Let the "completed: false" from opening pass before listening again.
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (token == _loadToken) _loading = false;
        });
      }
    }
  }

  /// Resolved streams of upcoming tracks; URLs expire, so not for long.
  final _resolved = <String, (Future<StreamInfo>, DateTime)>{};

  Future<StreamInfo> _resolve(Track track) {
    final hit = _resolved.remove(track.key);
    if (hit != null &&
        DateTime.now().difference(hit.$2) < const Duration(minutes: 20)) {
      return hit.$1;
    }
    return _sources[track.source]!.resolveStream(track);
  }

  /// Drops [track]'s prepared stream, e.g. after another version of it
  /// was chosen; plays it again from the start if it's the current one.
  Future<void> reloadTrack(Track track) async {
    _resolved.remove(track.key);
    if (_out == null && current?.key == track.key) await _playIndex(_index);
  }

  /// Gets the next track ready while this one plays: finds its stream
  /// (for imported/wave tracks that includes the YouTube search) and loads
  /// the first seconds of audio, so skipping starts almost at once.
  void _prefetchNext() {
    final i = _index + 1;
    if (i < _tracks.length) warm(_tracks[i]);
    if (fadeSeconds >= 1 && i < _tracks.length) {
      // A mix comes at the end of this song: know its tempo, and have the
      // second player made (starting libmpv takes a moment) well before.
      final cur = current;
      if (matchTempo && cur != null) bpmFor?.call(cur).ignore();
      _tailPlayer();
    }
  }

  Player _tailPlayer() => _tail ??= Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
  );

  /// Gets [track] ready to start instantly. Cheap to call often: the UI
  /// calls it when the pointer rests on a track or a finger touches it.
  void warm(Track track) {
    if (_resolved.containsKey(track.key) || track.key == current?.key) return;
    final local = localPathFor?.call(track);
    if (local != null && File(local).existsSync()) return;
    final source = _sources[track.source];
    if (source == null) return;
    final f = source.resolveStream(track);
    _resolved.removeWhere(
      (_, v) => DateTime.now().difference(v.$2) > const Duration(minutes: 20),
    );
    // Keep a handful: hovering down a list must not pile up requests.
    while (_resolved.length >= 6) {
      _resolved.remove(_resolved.keys.first);
    }
    _resolved[track.key] = (f, DateTime.now());
    f
        .then(
          (info) {
            if (info.hls && _resolved.containsKey(track.key)) {
              HlsProxy.instance.prefetch(info.url);
            }
            // Intro/outro bounds and tempo ready for a smooth mix.
            if (skipIntros) autoBounds?.call(track).ignore();
            if (matchTempo && fadeSeconds >= 1) bpmFor?.call(track).ignore();
          },
          onError: (Object _) {
            _resolved.remove(track.key);
          },
        )
        .ignore();
  }

  Future<void> _mpv(String name, String value) async {
    final native = _player.platform;
    if (native is NativePlayer) await native.setProperty(name, value);
  }

  /// In-memory cache only: the macOS sandbox refuses mpv's disk cache.
  Future<void> _configureMpv() async {
    try {
      await _mpv('cache-on-disk', 'no');
      await _mpv('cache', 'yes');
      await _mpv('demuxer-max-bytes', '${32 * 1024 * 1024}');
    } catch (e) {
      debugPrint('mpv config: $e');
    }
  }

  static Future<String> _playableUri(
    StreamInfo info, {
    bool proxy = true,
  }) async {
    if (info.url.isScheme('file')) return info.url.toFilePath();
    if (info.hls) {
      return proxy
          ? (await HlsProxy.instance.wrap(info.url)).toString()
          : info.url.toString();
    }
    if (info.chunked && info.contentLength != null && !info.hls) {
      return (await ChunkProxy.instance.wrap(
        info.url,
        info.contentLength!,
      )).toString();
    }
    return info.url.toString();
  }

  /// Applies sound settings: pitch via mpv `speed` (tempo corrected by the
  /// scaletempo filter), everything else as one FFmpeg filter graph.
  Future<void> applyFx(AudioFx fx) async {
    _fx = fx;
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      // Pitch kept by mpv itself unless a pitch shift is wanted (then the
      // speed carries the shift and our scaletempo restores the tempo).
      await native.setProperty(
        'audio-pitch-correction',
        fx.plainPitch ? 'yes' : 'no',
      );
      await native.setProperty(
        'speed',
        fx.mpvSpeedAt(_tempo).toStringAsFixed(6),
      );
      await native.setProperty('af', fx.mpvAf);
    } catch (e) {
      debugPrint('fx: $e');
    }
  }

  // --- DJ mix -----------------------------------------------------------------

  /// Start / end of the music in a track (e.g. SponsorBlock), or null.
  Future<({Duration? start, Duration? end})?> Function(Track track)? autoBounds;

  /// Tempo of a track in BPM, when known.
  Future<double?> Function(Track track)? bpmFor;

  /// Skip spoken intros and end skits of music videos.
  bool skipIntros = true;

  /// Bring the next song to the current one's tempo (±4 %) during a mix.
  bool matchTempo = true;

  String? _currentUri;
  bool _currentHls = false;

  /// Playback rate on top of the effects: 1, or a little off while a
  /// mixed-in song is brought to the previous one's tempo.
  double _tempo = 1;
  double _mixTempo = 1;
  Timer? _tempoEase;

  Player? _tail;
  Timer? _mix;
  bool _mixStarting = false;

  Future<void> _setTempo(double t) async {
    // With a pitch shift on, the tempo can't change without the pitch:
    // the mix then keeps each song's own tempo.
    if (!_fx.plainPitch) t = 1;
    _tempo = t;
    await _mpv('speed', _fx.mpvSpeedAt(t).toStringAsFixed(6));
  }

  // --- gapless ---------------------------------------------------------------

  /// The next song, already in mpv's playlist behind the current one.
  ({
    int index,
    String key,
    int token,
    StreamInfo info,
    String uri,
    Duration? start,
    Duration? end,
  })?
  _gapless;
  bool _gaplessPreparing = false;

  /// Without crossfade, songs follow each other with no gap at all: near
  /// the end of one, the next is handed to mpv, which plays it the moment
  /// this one ends (live albums and DJ sets flow on).
  void _maybeQueueNext(Duration pos) {
    if ((fadeSeconds >= 1 && _mixFailedToken != _loadToken) ||
        _gapless != null ||
        _gaplessPreparing ||
        _loading ||
        _mix != null ||
        _out != null ||
        sleepAfterTrack.value ||
        _index >= _tracks.length - 1 ||
        !_player.state.playing) {
      return;
    }
    final end = _trimEnd ?? mediaItem.value?.duration;
    if (end == null) return;
    final left = end - pos;
    if (left > const Duration(seconds: 15) ||
        left < const Duration(seconds: 2)) {
      return;
    }
    unawaited(_queueNext());
  }

  Future<void> _queueNext() async {
    _gaplessPreparing = true;
    final token = _loadToken;
    final i = _index + 1;
    final next = _tracks[i];
    bool stillSame() =>
        token == _loadToken &&
        _index + 1 == i &&
        i < _tracks.length &&
        _tracks[i].key == next.key &&
        _mix == null &&
        _out == null &&
        (fadeSeconds < 1 || _mixFailedToken == token);
    try {
      final local = localPathFor?.call(next);
      final isLocal = local != null && File(local).existsSync();
      final info = isLocal
          ? StreamInfo(Uri.file(local), duration: next.duration)
          : await _resolve(next);
      if (!stillSame()) return;
      final uri = await _playableUri(info);
      final trim = trimFor?.call(next);
      var start = trim?.start;
      var end = trim?.end;
      if (skipIntros && autoBounds != null) {
        final auto = await autoBounds!(next)
            .timeout(const Duration(milliseconds: 700))
            .catchError((Object _) => null);
        start ??= auto?.start;
        end ??= auto?.end;
      }
      if (!stillSame()) return;
      await _player.add(Media(uri, start: start));
      _gapless = (
        index: i,
        key: next.key,
        token: token,
        info: info,
        uri: uri,
        start: start,
        end: end,
      );
    } catch (e) {
      debugPrint('gapless ${next.title}: $e');
    } finally {
      _gaplessPreparing = false;
    }
  }

  /// The queued song plays now: catch up with it (no reopening).
  void _advanceGapless(
    ({
      int index,
      String key,
      int token,
      StreamInfo info,
      String uri,
      Duration? start,
      Duration? end,
    })
    g,
  ) {
    _gapless = null;
    if (g.index >= _tracks.length || _tracks[g.index].key != g.key) return;
    _leaving(skipped: false);
    final track = _tracks[g.index];
    _index = g.index;
    final token = ++_loadToken;
    _openedToken = token;
    _trimStart = g.start;
    _trimEnd = g.end;
    _endedByTrim = false;
    _currentUri = g.uri;
    _currentHls = g.info.hls;
    _normGain = _gainFor(track, g.info.loudnessDb);
    unawaited(_applyVolume());
    _onCopy = false;
    _copy = null;
    if (g.info.hls &&
        track.source != SourceKind.youtube &&
        seekableCopy != null) {
      _copy = seekableCopy!(g.info, track)..ignore();
    }
    final item = _toMediaItem(track);
    mediaItem.add(
      g.info.duration == null ? item : item.copyWith(duration: g.info.duration),
    );
    queueVersion.value++;
    unawaited(_maybeRefill());
    onTrackStarted?.call(track);
    _changed();
    _broadcastState();
    _prefetchNext();
    // Keep mpv's playlist to the one song that plays.
    unawaited(_player.remove(0));
  }

  /// Takes a queued next song back out of mpv's playlist.
  void _dropGapless() {
    if (_gapless == null) return;
    _gapless = null;
    unawaited(_player.remove(1));
  }

  /// Told when a song is left, for learning taste: how long it played,
  /// how long it is, and whether it was skipped (not played to its end).
  void Function(Track track, Duration played, Duration? length, bool skipped)?
  onTrackLeft;
  int _leftToken = -1;

  void _leaving({required bool skipped}) {
    final t = current;
    if (t == null || _out != null || _switching || _leftToken == _loadToken) {
      return;
    }
    _leftToken = _loadToken;
    final start = _trimStart ?? Duration.zero;
    final end = _trimEnd ?? mediaItem.value?.duration;
    onTrackLeft?.call(
      t,
      _player.state.position - start,
      end == null ? null : end - start,
      skipped,
    );
  }

  /// The queue changed under a queued next song: take it back out.
  void _checkGapless() {
    final g = _gapless;
    if (g == null) return;
    if (_index + 1 < _tracks.length && _tracks[_index + 1].key == g.key) {
      return;
    }
    _gapless = null;
    unawaited(_player.remove(1));
  }

  void _maybeMix(Duration pos) {
    if (fadeSeconds < 1 ||
        _mix != null ||
        _gapless != null ||
        _mixStarting ||
        _mixFailedToken == _loadToken ||
        _loading ||
        sleepAfterTrack.value ||
        _index >= _tracks.length - 1 ||
        !_player.state.playing) {
      return;
    }
    final end = _trimEnd ?? mediaItem.value?.duration;
    if (end == null || end < const Duration(seconds: 30)) return;
    final left = end - pos;
    // The hand-over takes ~2.5 s to prepare (see _startMix), more on a
    // slow network: begin early, so the crossfade keeps its full length.
    if (left > Duration(milliseconds: (fadeSeconds * 1000).round() + 4000) ||
        left < const Duration(seconds: 4)) {
      return;
    }
    unawaited(_startMix(pos));
  }

  /// The outgoing song moves to a second player (same moment, same
  /// sound), the main player starts the next one silently, and [_runMix]
  /// crosses them over.
  Future<void> _startMix(Duration pos) async {
    final uri = _currentUri;
    if (uri == null) return;
    _mixStarting = true;
    final token = _loadToken;
    try {
      // Tempo first (usually known already): the hand-over below must not
      // wait for anything.
      _mixTempo = 1;
      final bpm = bpmFor;
      if (matchTempo && _fx.plainPitch && bpm != null) {
        final next = _tracks[_index + 1];
        final both =
            await (
              bpm(_tracks[_index]).catchError((Object _) => null),
              bpm(next).catchError((Object _) => null),
            ).wait.timeout(
              // Fetched when the song started; if it isn't known by now,
              // the mix goes on at the song's own tempo.
              const Duration(milliseconds: 400),
              onTimeout: () => (null, null),
            );
        final (a, b) = both;
        if (a != null && b != null) {
          _mixTempo = (a * _tempo / b).clamp(0.96, 1.04);
        }
      }
      if (token != _loadToken) return;

      final tail = _tailPlayer();
      final native = tail.platform;
      if (native is NativePlayer) {
        await native.setProperty('cache-on-disk', 'no');
        await native.setProperty(
          'audio-pitch-correction',
          _fx.plainPitch ? 'yes' : 'no',
        );
        await native.setProperty(
          'demuxer-lavf-o',
          _currentHls ? 'http_persistent=0' : '',
        );
        await native.setProperty(
          'speed',
          _fx.mpvSpeedAt(_tempo).toStringAsFixed(6),
        );
        await native.setProperty('af', _fx.mpvAf);
      }
      _tailNormGain = _normGain;
      // The second player waits, silent and paused, a little ahead of this
      // one; when this one reaches that moment, they swap in one go. (Both
      // playing the song at once, slightly apart, sounded doubled.)
      final at = _player.state.position + const Duration(milliseconds: 2500);
      await tail.setVolume(0);
      await tail.open(Media(uri, start: at), play: false);
      await tail.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 300)); // buffer
      if (token != _loadToken) return;
      if (_player.state.position >= at) {
        throw StateError('the second player was too slow');
      }
      await _player.stream.position
          .firstWhere((p) => p >= at - const Duration(milliseconds: 25))
          .timeout(const Duration(seconds: 4));
      if (token != _loadToken) return;
      final started = Stopwatch()..start();
      unawaited(tail.play());
      lastMixSlip = _player.state.position - at;
      // Silent until it really plays (its sound device may take a moment
      // to start): only then does it take over, so there's no gap.
      await tail.stream.position
          .firstWhere((p) => p >= at + const Duration(milliseconds: 20))
          .timeout(const Duration(seconds: 2));
      lastMixTailLag = started.elapsed - const Duration(milliseconds: 20);
      if (token != _loadToken) return;
      unawaited(
        tail.setVolume(volume.value * _sleepGain * _tailNormGain * 100),
      );
      // From here the tail carries the old song; the main one goes on.
      _mixOldEnd = _trimEnd ?? mediaItem.value?.duration;
      _edgeGain = 0;
      await _applyVolume();
      await _playIndex(_index + 1, mixing: true);
    } catch (e) {
      debugPrint('mix: $e');
      _stopMix();
      // No mix this time: at least no pause, the next song follows
      // straight on (gapless) instead of after the old one has ended.
      if (token == _loadToken) _mixFailedToken = token;
    } finally {
      _mixStarting = false;
    }
  }

  /// The mix of this song failed: it hands over gapless instead.
  int _mixFailedToken = -1;

  /// Where the outgoing song's music ends (the fade must finish by then).
  Duration? _mixOldEnd;

  /// How far apart the two players were at the last hand-over (tests).
  @visibleForTesting
  Duration? lastMixSlip;

  /// Where the outgoing song is during a mix (the second player once it
  /// carries it), and the incoming one (tests look for stalls).
  @visibleForTesting
  ({Duration old, Duration incoming, bool handedOver}) get debugMixPositions {
    final t = _tail;
    final over = t != null && t.state.playing;
    return (
      old: over ? t.state.position : _player.state.position,
      incoming: _player.state.position,
      handedOver: over,
    );
  }

  /// How long the second player took to really start at the hand-over.
  @visibleForTesting
  Duration? lastMixTailLag;

  /// Equal-power crossfade: the new song rises while the old one falls.
  void _runMix() {
    final tail = _tail;
    if (tail == null) return;
    // Started late (slow network)? The fade is shortened so the old song
    // doesn't run out while the new one is still quiet.
    var total = fadeSeconds * 1000.0;
    final end = _mixOldEnd;
    if (end != null) {
      final left = (end - tail.state.position).inMilliseconds.toDouble();
      if (left < total) total = math.max(1500, left);
    }
    final clock = Stopwatch()..start();
    _mix?.cancel();
    _mix = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final x = (clock.elapsedMilliseconds / total).clamp(0.0, 1.0);
      _edgeGain = math.sin(x * math.pi / 2);
      _applyVolume();
      tail.setVolume(
        volume.value *
            _sleepGain *
            _tailNormGain *
            100 *
            math.cos(x * math.pi / 2),
      );
      if (x >= 1) {
        t.cancel();
        _mix = null;
        tail.stop();
        _easeTempo();
      }
    });
  }

  /// After a tempo-matched mix, drift back to the song's own tempo.
  void _easeTempo() {
    _tempoEase?.cancel();
    if ((_tempo - 1).abs() < 0.002) return;
    final from = _tempo;
    var step = 0;
    _tempoEase = Timer.periodic(const Duration(milliseconds: 250), (t) {
      step++;
      final x = (step / 60).clamp(0.0, 1.0); // ~15 s
      _setTempo(from + (1 - from) * Curves.easeInOut.transform(x));
      if (x >= 1) t.cancel();
    });
  }

  void _stopMix() {
    _mix?.cancel();
    _mix = null;
    _tempoEase?.cancel();
    _tail?.stop();
    if (_edgeGain != 1) {
      _edgeGain = 1;
      _applyVolume();
    }
  }

  AudioFx get fx => _fx;

  /// Sets an mpv property (diagnostics and tests).
  Future<void> debugSetProperty(String name, String value) => _mpv(name, value);

  /// Reads an mpv property (diagnostics and tests).
  Future<String> debugProperty(String name) async {
    final native = _player.platform;
    return native is NativePlayer ? native.getProperty(name) : '';
  }

  /// What is playing, for handing playback over to another device.
  @override
  Map<String, dynamic> snapshot() => {
    'queue': [for (final t in _tracks) t.toJson()],
    'index': _index,
    'positionMs': _localPosition.inMilliseconds,
    'playing': _localPlaying,
    'volume': volume.value,
    'durationMs': mediaItem.value?.duration?.inMilliseconds,
    // Imported songs play a YouTube version found on this device; the
    // other device must play exactly the same one, not search anew.
    'matches': _matchesAround(),
  };

  /// The exact versions imported songs play here (found on YouTube or
  /// chosen by hand), and how to take them from another device.
  Track? Function(Track imported)? matchOf;
  void Function(Track imported, Track version)? adoptMatch;

  Map<String, dynamic> _matchesAround() {
    final out = <String, dynamic>{};
    final f = matchOf;
    if (f == null || _index < 0) return out;
    for (var i = _index; i < _tracks.length && i <= _index + 5; i++) {
      final t = _tracks[i];
      if (t.source != SourceKind.match) continue;
      final m = f(t);
      if (m != null) out[t.key] = m.toJson();
    }
    return out;
  }

  /// Takes the versions a snapshot from another device came with.
  void adoptMatches(Map<String, dynamic> snap) {
    final adopt = adoptMatch;
    final m = snap['matches'];
    if (adopt == null || m is! Map) return;
    final queue = [
      for (final j in (snap['queue'] as List? ?? const []))
        Track.fromJson((j as Map).cast<String, dynamic>()),
    ];
    for (final t in queue) {
      final v = m[t.key];
      if (v is Map) {
        adopt(t, Track.fromJson(v.cast<String, dynamic>()));
        _resolved.remove(t.key); // a stream for another version, if any
      }
    }
  }

  /// Continues a [snapshot] taken on another device.
  @override
  Future<void> restore(Map<String, dynamic> snap) async {
    // Music arrives here: this device plays again, it's not a remote.
    leaveRemote();
    adoptMatches(snap);
    final queue = [
      for (final j in (snap['queue'] as List? ?? const []))
        Track.fromJson((j as Map).cast<String, dynamic>()),
    ];
    final index = snap['index'] as int? ?? 0;
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    unawaited(
      playList(
        queue,
        index,
        startAt: Duration(milliseconds: snap['positionMs'] as int? ?? 0),
      ),
    );
  }

  /// Volume chosen by the user, 0…1 (tests run muted).
  final volume = ValueNotifier<double>(1);

  /// Seconds of fade-out at the end of a track and fade-in at the start
  /// of the next ("плавные переходы"); 0 switches it off.
  double fadeSeconds = 0;

  /// Fade multiplier on top of [volume]: track edges and the sleep timer.
  double _edgeGain = 1;
  double _sleepGain = 1;

  @override
  Future<void> setVolume(double v) {
    if (_out != null) {
      volume.value = v.clamp(0.0, 1.0);
      return _out!.send('volume', {'v': volume.value});
    }
    volume.value = v.clamp(0.0, 1.0);
    _changed();
    return _applyVolume();
  }

  Future<void> _applyVolume() => _player.setVolume(
    volume.value * _edgeGain * _sleepGain * _normGain * 100,
  );

  /// Evens out loudness between tracks ("Выравнивать громкость").
  bool normalize = true;

  /// Loudness remembered for tracks played before (cached or downloaded
  /// copies don't come with it), and where to remember new ones.
  double? Function(Track track)? storedLoudness;
  void Function(Track track, double loudnessDb)? saveLoudness;

  /// This track's correction (1 = as is).
  double _normGain = 1;
  double _tailNormGain = 1;

  /// Where tracks are brought to, in YouTube's loudness terms: most of
  /// today's music sits 5–9 dB above YouTube's (quiet) reference, so
  /// levelling to the reference itself made nearly everything quieter.
  /// Around this level typical songs stay as they are, the loudest come
  /// down a little and quiet ones (old records, acoustic) come up.
  static const _targetDb = 6.0;

  double _gainFor(Track track, double? loudnessDb) {
    final db = loudnessDb ?? storedLoudness?.call(track);
    if (loudnessDb != null) saveLoudness?.call(track, loudnessDb);
    if (!normalize || db == null) return 1;
    // Up by at most 3 dB: more would distort without a limiter.
    return math.pow(10, (_targetDb - db).clamp(-9.0, 3.0) / 20).toDouble();
  }

  /// Switches normalisation on or off for what plays now too.
  Future<void> setNormalize(bool on) async {
    if (on == normalize) return;
    normalize = on;
    final t = current;
    _normGain = t == null ? 1 : _gainFor(t, null);
    await _applyVolume();
  }

  /// Called on every position update: shapes the volume at track edges.
  void _fadeAt(Duration pos) {
    // During a mix (or when one will follow) the mix shapes the volume.
    if (_mix != null || (fadeSeconds >= 1 && _index < _tracks.length - 1)) {
      return;
    }
    var gain = 1.0;
    final fade = fadeSeconds;
    final total = _trimEnd ?? mediaItem.value?.duration;
    if (fade > 0 && total != null && total > const Duration(seconds: 20)) {
      final fadeIn = fade < 1.5 ? fade : 1.5;
      final p = (pos - (_trimStart ?? Duration.zero)).inMilliseconds / 1000;
      final left = (total - pos).inMilliseconds / 1000;
      if (p < fadeIn) gain = (p / fadeIn).clamp(0.05, 1.0);
      if (left < fade) gain = (left / fade).clamp(0.0, 1.0);
    }
    if ((gain - _edgeGain).abs() > 0.01 || (gain == 1 && _edgeGain != 1)) {
      _edgeGain = gain;
      _applyVolume();
    }
  }

  // --- sleep timer ----------------------------------------------------------

  /// When playback will stop, or null. [sleepAfterTrack] instead stops at
  /// the end of the current track.
  final sleepAt = ValueNotifier<DateTime?>(null);
  final sleepAfterTrack = ValueNotifier<bool>(false);
  Timer? _sleepTimer;

  void setSleepTimer(Duration? after, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepGain = 1;
    _applyVolume();
    sleepAfterTrack.value = endOfTrack;
    sleepAt.value = after == null ? null : DateTime.now().add(after);
    if (after == null) return;
    // The last ten seconds fade away instead of cutting off.
    const fade = Duration(seconds: 10);
    final wait = after > fade ? after - fade : Duration.zero;
    _sleepTimer = Timer(wait, () {
      var step = 0;
      _sleepTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
        step++;
        _sleepGain = (1 - step / 20).clamp(0.0, 1.0);
        _applyVolume();
        if (step >= 20) {
          t.cancel();
          pause();
          _sleepGain = 1;
          _applyVolume();
          sleepAt.value = null;
        }
      });
    });
  }

  /// Android Auto's menu and voice requests (set in main()).
  CarBrowser? car;

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async => await car?.children(parentMediaId) ?? const [];

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async => car?.play(mediaId);

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async => await car?.find(query) ?? const [];

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async => car?.playSearch(query);

  @override
  Future<void> play() {
    if (_out != null) return _remoteSend('play', playing: true);
    return _player.play();
  }

  @override
  Future<void> pause() {
    if (_out != null) return _remoteSend('pause', playing: false);
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_out != null) {
      return _remoteSend(
        'seek',
        args: {'ms': position.inMilliseconds},
        at: position,
      );
    }
    // The old song while the next one loads: a seek would land on the
    // wrong track.
    if (_switching) return;
    Future<void>.delayed(const Duration(milliseconds: 300), _changed);
    final copy = _copy;
    if (copy == null || _onCopy) return _player.seek(position);
    await _seekViaCopy(copy, position);
  }

  Future<void> _seekViaCopy(Future<String> copy, Duration position) async {
    final token = _loadToken;
    final wasPlaying = _player.state.playing;
    _loading = true;
    _broadcastState();
    try {
      final path = await copy.timeout(const Duration(seconds: 30));
      if (token != _loadToken) return; // track changed meanwhile
      _onCopy = true;
      await _player.open(Media(path, start: position), play: wasPlaying);
    } catch (e) {
      debugPrint('seek copy: $e');
      if (token != _loadToken) return; // another track by now
      await _player.seek(position); // best effort
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (token == _loadToken) _loading = false;
        _broadcastState();
      });
    }
  }

  @override
  Future<void> skipToNext() {
    if (_out != null) return _out!.send('next');
    return _playIndex(_index + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_out != null) return _out!.send('prev');
    // Like every player: restart the track unless we're near its start.
    final start = _trimStart ?? Duration.zero;
    if (_player.state.position > start + const Duration(seconds: 3)) {
      await _player.seek(start);
    } else {
      await _playIndex(_index - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) {
    if (_out != null) {
      return _out!.send('item', {'i': index + _remoteOffset});
    }
    return _playIndex(index);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _broadcastState() {
    final st = _player.state;
    final playing = _out != null ? _remotePlaying : _localPlaying;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _loading || st.buffering
            ? AudioProcessingState.buffering
            : (_index < 0
                  ? AudioProcessingState.idle
                  : AudioProcessingState.ready),
        playing: playing,
        updatePosition: _out != null ? _remotePosition() : _localPosition,
        bufferedPosition: st.buffer,
        speed: _fx.speed,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
  }

  // --- remote mode ("Spotify Connect") --------------------------------------

  _Output? _out;

  /// Name of the device the music plays on while this one is its remote;
  /// null when it plays here.
  final output = ValueNotifier<String?>(null);
  String? get outputId => _out?.id;

  bool _remotePlaying = false;
  int _remotePosMs = 0;
  DateTime _remoteAt = DateTime(0);
  int _remoteOffset = 0;
  Timer? _remoteTick;
  double _localVolume = 1;

  bool get isPlaying => _out != null ? _remotePlaying : _localPlaying;

  /// Where playback is now, here or on the device this one controls.
  Duration get position => _out != null ? _remotePosition() : _localPosition;

  /// Becomes the remote for device [id]: this player stops making sound and
  /// shows what plays there; its buttons control it.
  void playOn(
    String id,
    String name,
    Future<void> Function(String op, [Map<String, dynamic>? args]) send,
  ) {
    if (_out == null) _localVolume = volume.value;
    _stopMix();
    _dropGapless();
    _player.pause();
    _out = _Output(id, send);
    output.value = name;
    _remoteTick?.cancel();
    _remoteTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_remotePlaying) _positionCtl.add(_remotePosition());
    });
    _broadcastState();
  }

  /// Back to playing here (what was loaded stays paused).
  void leaveRemote() {
    if (_out == null) return;
    _out = null;
    output.value = null;
    _remoteTick?.cancel();
    volume.value = _localVolume;
    _applyVolume();
    _playingCtl.add(_localPlaying);
    _positionCtl.add(_localPosition);
    _broadcastState();
  }

  Duration _remotePosition() {
    final moving = _remotePlaying
        ? DateTime.now().difference(_remoteAt).inMilliseconds
        : 0;
    final d = mediaItem.value?.duration?.inMilliseconds;
    final p = _remotePosMs + moving;
    return Duration(milliseconds: d != null && p > d ? d : p);
  }

  /// What the device this one controls is doing (from its state message,
  /// [at] by our clock).
  void remoteState(Map<String, dynamic> snap, DateTime at) {
    if (_out == null) return;
    final queue = [
      for (final j in (snap['queue'] as List? ?? const []))
        Track.fromJson((j as Map).cast<String, dynamic>()),
    ];
    final index = snap['index'] as int? ?? -1;
    _remoteOffset = snap['offset'] as int? ?? 0;
    final changedTrack =
        index < 0 ||
        index >= queue.length ||
        _index < 0 ||
        _index >= _tracks.length ||
        _tracks[_index].key != queue[index].key;
    _tracks
      ..clear()
      ..addAll(queue);
    _index = index;
    if (queue.isNotEmpty) this.queue.add(queue.map(_toMediaItem).toList());
    queueVersion.value++;
    if (index >= 0 && index < queue.length) {
      final ms = snap['durationMs'] as int?;
      final item = _toMediaItem(queue[index]);
      if (changedTrack || mediaItem.value?.id != item.id) {
        mediaItem.add(
          ms == null
              ? item
              : item.copyWith(duration: Duration(milliseconds: ms)),
        );
      }
    }
    _remotePlaying = snap['playing'] == true;
    _remotePosMs = snap['positionMs'] as int? ?? 0;
    _remoteAt = at;
    volume.value = (snap['volume'] as num?)?.toDouble() ?? volume.value;
    _playingCtl.add(_remotePlaying);
    _positionCtl.add(_remotePosition());
    _broadcastState();
  }

  /// Sends [op] and shows its effect right away (the device confirms with
  /// its next state).
  Future<void> _remoteSend(
    String op, {
    bool? playing,
    Map<String, dynamic>? args,
    Duration? at,
  }) {
    if (at != null) {
      _remotePosMs = at.inMilliseconds;
      _remoteAt = DateTime.now();
    }
    if (playing != null) {
      _remotePosMs = _remotePosition().inMilliseconds;
      _remoteAt = DateTime.now();
      _remotePlaying = playing;
      _playingCtl.add(playing);
    }
    _positionCtl.add(_remotePosition());
    _broadcastState();
    return _out!.send(op, args);
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
    id: t.key,
    title: t.displayTitle,
    artist: t.artist,
    duration: t.duration,
    artUri: t.artworkUrl == null
        ? null
        : (t.artworkUrl!.startsWith('/')
              ? Uri.file(t.artworkUrl!)
              : Uri.parse(t.artworkUrl!)),
  );
}

class _Output {
  _Output(this.id, this.send);
  final String id;
  final Future<void> Function(String op, [Map<String, dynamic>? args]) send;
}
