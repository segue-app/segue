import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import 'player_handler.dart';

/// Where listening stopped: the song, the moment in it and the queue, so
/// the home screen can offer to go on after the app was closed.
class ResumePoint {
  ResumePoint(this.library, this.player);

  final LibraryStore library;
  final SegueAudioHandler player;
  Timer? _timer;
  bool _wasPlaying = false;

  static const _key = 'resume';

  /// Older than this: not worth offering.
  static const _keepFor = Duration(days: 14);

  void attach() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
  }

  void _save() {
    final playing = player.isPlaying;
    // Once more after a pause: the moment it stopped.
    if (!playing && !_wasPlaying) return;
    _wasPlaying = playing;
    if (player.current == null) return;
    try {
      final snap = player.snapshot();
      final queue = snap['queue'] as List;
      final index = snap['index'] as int;
      final from = (index - 50).clamp(0, queue.length);
      snap['queue'] = queue.sublist(from, (index + 150).clamp(from, queue.length));
      snap['index'] = index - from;
      snap['playing'] = true;
      snap['context'] = player.playContext.value;
      snap['wave'] = player.waveTitle.value;
      snap['at'] = DateTime.now().millisecondsSinceEpoch;
      library.setMeta(_key, jsonEncode(snap));
    } catch (_) {}
  }

  /// The last saved point, if recent.
  ({Map<String, dynamic> snap, Track track, Duration position, String? wave})?
  load() {
    try {
      final snap = jsonDecode(library.getMeta(_key) ?? '') as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(snap['at'] as int? ?? 0);
      if (DateTime.now().difference(at) > _keepFor) return null;
      final queue = snap['queue'] as List;
      final track = Track.fromJson(
        (queue[snap['index'] as int] as Map).cast<String, dynamic>(),
      );
      return (
        snap: snap,
        track: track,
        position: Duration(milliseconds: snap['positionMs'] as int? ?? 0),
        wave: snap['wave'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Plays from where it stopped.
  Future<void> resume(Map<String, dynamic> snap) async {
    await player.restore(snap);
    final ctx = snap['context'];
    if (ctx is String) player.playContext.value = ctx;
  }

  void dispose() => _timer?.cancel();
}

/// Created in main() and overridden there.
final resumeProvider = Provider<ResumePoint>(
  (ref) => throw UnimplementedError('resumeProvider is overridden in main()'),
);
