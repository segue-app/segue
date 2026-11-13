import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';

/// Sound settings: 10-band EQ, speed and pitch, applied as mpv audio
/// filters the same way on every platform.
///
/// Only filters present in media_kit's FFmpeg build may be used: it ships
/// `equalizer` (plus mpv's own `scaletempo`) but not aecho, volume,
/// compressors etc. An unknown filter in the graph crashes libmpv.
@immutable
class AudioFx {
  const AudioFx({
    this.eqOn = false,
    this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.preset = 'Ровно',
    this.speed = 1,
    this.semitones = 0,
  });

  final bool eqOn;

  /// dB per band, −12…+12, for [bands].
  final List<double> gains;
  final String preset;

  /// Playback speed 0.5…2, pitch kept.
  final double speed;

  /// Pitch shift in semitones −12…+12, tempo kept.
  final double semitones;

  static const bands = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  static const presets = <String, List<double>>{
    'Ровно': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Бас': [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
    'Вокал': [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1],
    'Рок': [4, 3, 2, 0, -1, -1, 1, 2, 3, 4],
    'Электроника': [5, 4, 1, 0, -2, 1, 0, 2, 4, 5],
    'Хип-хоп': [5, 4, 2, 3, -1, -1, 1, 0, 2, 3],
    'Поп': [-1, 0, 2, 3, 4, 3, 1, 0, -1, -1],
    'Акустика': [3, 2, 1, 1, 2, 2, 3, 3, 2, 1],
    'Ночь': [3, 2, 1, 0, -1, -2, -3, -4, -5, -6],
  };

  bool get isNeutral =>
      (!eqOn || gains.every((g) => g == 0)) && speed == 1 && semitones == 0;

  /// mpv `speed`: carries the pitch shift (tempo is corrected by scaletempo).
  double get mpvSpeed => math.pow(2, semitones / 12).toDouble();

  /// No pitch shift: speed (and a DJ mix's tempo) goes straight to mpv's
  /// `speed` with its own pitch correction (scaletempo2), which follows
  /// speed changes smoothly and keeps the pitch.
  bool get plainPitch => semitones == 0;

  /// mpv `speed` for these settings at a mix [tempo].
  double mpvSpeedAt(double tempo) =>
      plainPitch ? speed * tempo : mpvSpeed * tempo;

  /// mpv `af` for these settings: EQ only when the pitch is plain (speed
  /// is handled by mpv itself), else EQ plus our tempo correction.
  String get mpvAf {
    if (!plainPitch) return mpvFilters;
    return [
      if (eqOn)
        for (var i = 0; i < bands.length; i++)
          if (gains[i].abs() >= 0.05)
            'lavfi=[equalizer=f=${bands[i]}:t=o:w=1:g=${gains[i].toStringAsFixed(1)}]',
    ].join(',');
  }

  /// mpv `af` value for these settings ('' when nothing to do).
  ///
  /// EQ bands first (one lavfi graph each), tempo correction last: libmpv
  /// fails to configure a lavfi graph placed after scaletempo.
  String get mpvFilters {
    final parts = <String>[];
    if (eqOn) {
      for (var i = 0; i < bands.length; i++) {
        final g = gains[i];
        if (g.abs() < 0.05) continue;
        parts.add(
          'lavfi=[equalizer=f=${bands[i]}:t=o:w=1:g=${g.toStringAsFixed(1)}]',
        );
      }
    }
    // Tempo: plays at [speed] whatever the pitch shift did to it.
    final tempo = speed / mpvSpeed;
    if ((tempo - 1).abs() > 1e-6) {
      parts.add('scaletempo=scale=${tempo.toStringAsFixed(6)}');
    }
    return parts.join(',');
  }

  AudioFx copyWith({
    bool? eqOn,
    List<double>? gains,
    String? preset,
    double? speed,
    double? semitones,
  }) => AudioFx(
    eqOn: eqOn ?? this.eqOn,
    gains: gains ?? this.gains,
    preset: preset ?? this.preset,
    speed: speed ?? this.speed,
    semitones: semitones ?? this.semitones,
  );

  Map<String, Object> toJson() => {
    'eqOn': eqOn,
    'gains': gains,
    'preset': preset,
    'speed': speed,
    'semitones': semitones,
  };

  factory AudioFx.fromJson(Map<String, dynamic> j) {
    const d = AudioFx();
    double n(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    final g = (j['gains'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return AudioFx(
      eqOn: j['eqOn'] as bool? ?? d.eqOn,
      gains: g != null && g.length == bands.length ? g : d.gains,
      preset: j['preset'] as String? ?? d.preset,
      speed: n('speed', d.speed),
      semitones: n('semitones', d.semitones),
    );
  }
}

class AudioFxNotifier extends Notifier<AudioFx> {
  static const _key = 'audio_fx';

  @override
  AudioFx build() {
    final raw = ref.read(libraryProvider).getMeta(_key);
    if (raw == null) return const AudioFx();
    try {
      return AudioFx.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AudioFx();
    }
  }

  void update(AudioFx Function(AudioFx fx) change) {
    state = change(state);
    ref.read(libraryProvider)
      ..setMeta(_key, jsonEncode(state.toJson()))
      ..touchPrefs();
  }
}

final audioFxProvider = NotifierProvider<AudioFxNotifier, AudioFx>(
  AudioFxNotifier.new,
);
