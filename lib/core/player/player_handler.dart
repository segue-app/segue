import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../models/track.dart';
import '../sources/music_source.dart';
import 'audio_fx.dart';
import 'chunked_source.dart';
import 'hls_proxy.dart';

/// What device-to-device handoff needs from a player.
abstract interface class PlaybackControl {
  Map<String, dynamic> snapshot();
  Future<void> restore(Map<String, dynamic> snapshot);
  Future<void> pause();
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
    s.playing.listen((_) => _broadcastState());
    s.buffering.listen((_) => _broadcastState());
    s.completed.listen((done) {
      // The end of a track, not the reset that comes with opening the next.
      if (done && !_loading) _trackEnded();
    });
    s.position.listen((pos) {
      _fadeAt(pos);
      // A trimmed track ends where its trim says.
      final end = _trimEnd;
      if (end != null && pos >= end && !_loading && !_endedByTrim) {
        _endedByTrim = true;
        _trackEnded();
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
  bool _loading = false;
  AudioFx _fx = const AudioFx();

  List<Track> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  Track? get current =>
      _index >= 0 && _index < _tracks.length ? _tracks[_index] : null;

  Stream<Duration> get positionStream => _player.stream.position;

  /// Duration of the current track as published in [mediaItem], which
  /// prefers the source's exact value over the player's estimate.
  Stream<Duration?> get durationStream => mediaItem.map((m) => m?.duration);
  Stream<bool> get playingStream => _player.stream.playing;

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

  /// Bumps on every queue change (order, length or current position).
  final queueVersion = ValueNotifier<int>(0);

  /// Endless mode ("Волна"): fetches more tracks as the queue runs out.
  Future<List<Track>> Function()? _refill;
  bool _refilling = false;

  /// Title of the running wave, null for an ordinary queue.
  final waveTitle = ValueNotifier<String?>(null);

  void _queueChanged() {
    queue.add(_tracks.map(_toMediaItem).toList());
    queueVersion.value++;
  }

  /// Replaces the queue with [list] and starts playing [list[start]].
  Future<void> playList(
    List<Track> list,
    int start, {
    Duration? startAt,
  }) async {
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

  Future<void> addNext(Track t) async {
    _tracks.insert(_index + 1, t);
    _queueChanged();
    _prefetchNext();
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

  Future<void> _playIndex(int i, {Duration? startAt}) async {
    if (i < 0 || i >= _tracks.length) return;
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
      debugPrint('load ${track.title}: opened in ${sw.elapsedMilliseconds} ms');
      onTrackStarted?.call(track);
      _prefetchNext();
    } catch (e) {
      if (token != _loadToken) return;
      debugPrint('play ${track.title}: $e');
      errors.add('Не удалось воспроизвести «${track.title}»');
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

  /// Gets the next track ready while this one plays: finds its stream
  /// (for imported/wave tracks that includes the YouTube search) and loads
  /// the first seconds of audio, so skipping starts almost at once.
  void _prefetchNext() {
    final i = _index + 1;
    if (i < _tracks.length) warm(_tracks[i]);
  }

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
      await native.setProperty('audio-pitch-correction', 'no');
      await native.setProperty('speed', fx.mpvSpeed.toStringAsFixed(6));
      await native.setProperty('af', fx.mpvFilters);
    } catch (e) {
      debugPrint('fx: $e');
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
    'positionMs': _player.state.position.inMilliseconds,
    'playing': _player.state.playing,
  };

  /// Continues a [snapshot] taken on another device.
  @override
  Future<void> restore(Map<String, dynamic> snap) async {
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

  Future<void> setVolume(double v) {
    volume.value = v.clamp(0.0, 1.0);
    return _applyVolume();
  }

  Future<void> _applyVolume() =>
      _player.setVolume(volume.value * _edgeGain * _sleepGain * 100);

  /// Called on every position update: shapes the volume at track edges.
  void _fadeAt(Duration pos) {
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

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
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
      await _player.seek(position); // best effort
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (token == _loadToken) _loading = false;
        _broadcastState();
      });
    }
  }

  @override
  Future<void> skipToNext() => _playIndex(_index + 1);

  @override
  Future<void> skipToPrevious() async {
    // Like every player: restart the track unless we're near its start.
    final start = _trimStart ?? Duration.zero;
    if (_player.state.position > start + const Duration(seconds: 3)) {
      await _player.seek(start);
    } else {
      await _playIndex(_index - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) => _playIndex(index);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _broadcastState() {
    final st = _player.state;
    final playing = st.playing;
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
        updatePosition: st.position,
        bufferedPosition: st.buffer,
        speed: _fx.speed,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
    id: t.key,
    title: t.title,
    artist: t.artist,
    duration: t.duration,
    artUri: t.artworkUrl == null
        ? null
        : (t.artworkUrl!.startsWith('/')
              ? Uri.file(t.artworkUrl!)
              : Uri.parse(t.artworkUrl!)),
  );
}
