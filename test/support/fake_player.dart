import 'dart:async';

import 'package:segue/core/models/track.dart';
import 'package:segue/core/player/player_handler.dart';

/// A player that records what it was told to do.
class FakePlayer implements PlaybackControl {
  Map<String, dynamic> state = {
    'queue': [],
    'index': -1,
    'positionMs': 0,
    'playing': false,
  };
  bool paused = false;

  @override
  Map<String, dynamic> snapshot() => state;

  @override
  Future<void> restore(Map<String, dynamic> s) async {
    state = {...s, 'playing': true};
    _c.add(null);
  }

  @override
  Future<void> pause() async {
    paused = true;
    state = {...state, 'playing': false};
    _c.add(null);
  }

  final _c = StreamController<void>.broadcast();
  final calls = <String>[];

  @override
  Stream<void> get stateChanges => _c.stream;
  @override
  Future<void> play() async {
    calls.add('play');
    state = {...state, 'playing': true};
    _c.add(null);
  }

  @override
  Future<void> seek(Duration p) async {
    calls.add('seek ${p.inSeconds}');
    state = {...state, 'positionMs': p.inMilliseconds};
    _c.add(null);
  }

  @override
  Future<void> addNext(Track t) async {
    calls.add('add ${t.id}');
    final q = List.of(state['queue'] as List);
    final i = state['index'] as int;
    q.insert(i + 1, t.toJson());
    state = {...state, 'queue': q};
    _c.add(null);
  }

  @override
  Future<void> skipToNext() async => calls.add('next');
  @override
  Future<void> skipToPrevious() async => calls.add('prev');
  @override
  Future<void> skipToQueueItem(int i) async => calls.add('item $i');
  @override
  Future<void> setVolume(double v) async {
    calls.add('volume $v');
    state = {...state, 'volume': v};
    _c.add(null);
  }
}

