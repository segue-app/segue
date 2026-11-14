import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_handler.dart';
import 'light_devices.dart';

/// How the lights move with the music.
enum LightEffect {
  /// A flash on every beat, brightest on the first of the bar.
  pulse,

  /// A new colour of the cover on every bar, a softer flash on the beats.
  bars,
}

/// Lights in time with the music: strips, lamps and the RGB of a computer
/// flash on the beats. The beats are known ahead (from the analysis), so
/// the light comes with the beat, not after it, as with apps that listen.
class LightSync {
  LightSync({required this.player, this.load, this.save}) {
    _restore();
  }

  final SegueAudioHandler player;
  final String? Function()? load;
  final void Function(String json)? save;

  final devices = ValueNotifier<List<LightDevice>>(const []);
  final enabled = ValueNotifier(false);
  LightEffect effect = LightEffect.pulse;

  /// The light's own delay plus the sound's (Bluetooth headphones are
  /// late): the beat is shown this much ahead (ms).
  int latencyMs = 90;

  /// Colours of the cover playing, the first the accent.
  List<Rgb> palette = const [(r: 255, g: 154, b: 118)];

  Timer? _timer;
  StreamSubscription<bool>? _playing;
  double _lastPhase = 1;
  int _bar = 0;

  void _restore() {
    try {
      final j = jsonDecode(load?.call() ?? '{}') as Map<String, dynamic>;
      effect = LightEffect.values.firstWhere(
        (e) => e.name == j['effect'],
        orElse: () => LightEffect.pulse,
      );
      latencyMs = (j['latency'] as num?)?.toInt() ?? latencyMs;
      devices.value = [
        for (final d in (j['devices'] as List? ?? const []))
          ?LightDevice.fromJson((d as Map).cast<String, dynamic>()),
      ];
      if (j['on'] == true) setEnabled(true);
    } catch (_) {}
  }

  void _persist() => save?.call(
    jsonEncode({
      'on': enabled.value,
      'effect': effect.name,
      'latency': latencyMs,
      'devices': [for (final d in devices.value) d.toJson()],
    }),
  );

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    player.wantBeats = on;
    _persist();
    _timer?.cancel();
    _timer = null;
    await _playing?.cancel();
    _playing = null;
    if (!on) {
      for (final d in devices.value) {
        await d.close();
      }
      return;
    }
    for (final d in devices.value) {
      await d.open();
    }
    devices.value = [...devices.value]; // statuses changed
    // 30 frames a second while music plays; paused, one dim frame and
    // nothing more.
    _playing = player.playingStream.listen(_follow);
    _follow(player.isPlayingNow);
  }

  void _follow(bool playing) {
    if (playing) {
      _timer ??= Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _tick(),
      );
    } else {
      _timer?.cancel();
      _timer = null;
      _tick();
    }
  }

  Future<void> add(LightDevice d) async {
    devices.value = [...devices.value, d];
    if (enabled.value) {
      await d.open();
      devices.value = [...devices.value];
    }
    _persist();
  }

  Future<void> remove(LightDevice d) async {
    await d.close();
    devices.value = [...devices.value]..remove(d);
    _persist();
  }

  void setEffect(LightEffect e) {
    effect = e;
    devices.value = [...devices.value]; // the settings show it
    _persist();
  }

  void setLatency(int ms) {
    latencyMs = ms;
    _persist();
  }

  /// Colour and brightness for this moment.
  @visibleForTesting
  static ({Rgb color, double level, bool beat}) look({
    required LightEffect effect,
    required List<Rgb> palette,
    required ({double phase, int beatInBar, double bpm})? beat,
    required bool playing,
    required int bar,
    required bool newBeat,
  }) {
    final base = palette.isEmpty ? (r: 255, g: 255, b: 255) : palette.first;
    if (!playing) return (color: base, level: 0.25, beat: false);
    if (beat == null) return (color: base, level: 0.6, beat: false);
    final strong = beat.beatInBar == 0;
    // A flash that fades over the beat: sharp, then soft.
    final decay = math.exp(-beat.phase * 5);
    final color = effect == LightEffect.bars && palette.isNotEmpty
        ? palette[bar % palette.length]
        : base;
    final peak = effect == LightEffect.bars
        ? (strong ? 1.0 : 0.75)
        : (strong ? 1.0 : 0.65);
    final floor = effect == LightEffect.bars ? 0.45 : 0.12;
    return (color: color, level: floor + (peak - floor) * decay, beat: newBeat);
  }

  void _tick() {
    if (devices.value.isEmpty) return;
    final b = player.beatNow(ahead: latencyMs / 1000);
    var newBeat = false;
    if (b != null) {
      newBeat = b.phase < _lastPhase - 0.5;
      if (newBeat && b.beatInBar == 0) _bar++;
      _lastPhase = b.phase;
    }
    final l = look(
      effect: effect,
      palette: palette,
      beat: b,
      playing: player.isPlayingNow,
      bar: _bar,
      newBeat: newBeat,
    );
    for (final d in devices.value) {
      d.frame(l.color, l.level, beat: l.beat);
    }
  }
}

/// Set in main(); null in tests and tools.
final lightSyncProvider = Provider<LightSync?>((ref) => null);
