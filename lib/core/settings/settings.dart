import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';

enum BackdropStyle { living, calm, plain }

/// How the sung line lights up.
enum LyricsStyle {
  /// Light sweeps through each word as it's sung (karaoke).
  sweep,

  /// Each word pops in when its turn comes.
  pop,

  /// The whole line lights up at once.
  line,
}

enum LyricsAlign { left, center }

/// Look-and-feel options, stored on this device.
@immutable
class AppSettings {
  const AppSettings({
    this.accentFromCover = true,
    this.accent = const Color(0xFFFF9A76),
    this.backdrop = BackdropStyle.living,
    this.backdropSpeed = 1,
    this.backdropIntensity = 1,
    this.font = 'Manrope',
    this.lyricsSize = 28,
    this.wavyProgress = true,
    this.glass = true,
    this.reduceMotion = false,
    this.textScale = 1,
    this.lyricsStyle = LyricsStyle.sweep,
    this.lyricsBlur = true,
    this.lyricsGlow = 0.6,
    this.lyricsAlign = LyricsAlign.left,
    this.lyricsOffsetMs = 0,
    this.lyricsLift = true,
    this.depth3d = true,
    this.fadeSeconds = 0,
    this.lyricsTranslate = false,
    this.notchIsland = true,
    this.skipIntros = true,
    this.normalizeVolume = true,
    this.offlineCache = true,
    this.matchTempo = true,
    this.desktopWidget = false,
  });

  /// Take the accent colour from the playing track's cover.
  final bool accentFromCover;
  final Color accent;
  final BackdropStyle backdrop;

  /// 0.2 … 2.5, multiplies the backdrop's motion.
  final double backdropSpeed;

  /// 0.4 … 1.4, how bright the colour clouds are.
  final double backdropIntensity;
  final String font;
  final double lyricsSize;
  final bool wavyProgress;
  final bool glass;
  final bool reduceMotion;
  final double textScale;

  final LyricsStyle lyricsStyle;

  /// Soft blur on lines away from the current one (depth of field).
  final bool lyricsBlur;

  /// 0 … 1, glow around sung words.
  final double lyricsGlow;
  final LyricsAlign lyricsAlign;

  /// Shift lyrics earlier (−) or later (+) when they run off the song.
  final int lyricsOffsetMs;

  /// The word being sung lifts slightly.
  final bool lyricsLift;

  /// Perspective: panels turned toward the centre and lyrics lines
  /// curving away like a wheel.
  final bool depth3d;

  /// Seconds of fade between tracks (0 = off).
  final double fadeSeconds;

  /// Show a translation under each lyrics line.
  final bool lyricsTranslate;

  /// MacBooks: now playing around the camera notch.
  final bool notchIsland;

  /// Skip spoken intros / end skits of music videos (SponsorBlock).
  final bool skipIntros;

  /// Even out loudness between tracks.
  final bool normalizeVolume;

  /// Keep recently played tracks on the device: instant start, offline.
  final bool offlineCache;

  /// Mixes bring the next song to the current tempo, like a DJ.
  final bool matchTempo;

  /// macOS: a now-playing card on the desktop.
  final bool desktopWidget;

  static const fonts = [
    'Manrope',
    'Inter',
    'Golos Text',
    'Montserrat',
    'Unbounded',
    'Nunito',
  ];
  static const accents = [
    Color(0xFFFF9A76),
    Color(0xFFFF6B81),
    Color(0xFFB98CFF),
    Color(0xFF6EA8FF),
    Color(0xFF4FD1C5),
    Color(0xFF7EE081),
    Color(0xFFFFD166),
    Color(0xFFF4F1EC),
  ];

  AppSettings copyWith({
    bool? accentFromCover,
    Color? accent,
    BackdropStyle? backdrop,
    double? backdropSpeed,
    double? backdropIntensity,
    String? font,
    double? lyricsSize,
    bool? wavyProgress,
    bool? glass,
    bool? reduceMotion,
    double? textScale,
    LyricsStyle? lyricsStyle,
    bool? lyricsBlur,
    double? lyricsGlow,
    LyricsAlign? lyricsAlign,
    int? lyricsOffsetMs,
    bool? lyricsLift,
    bool? depth3d,
    double? fadeSeconds,
    bool? lyricsTranslate,
    bool? notchIsland,
    bool? skipIntros,
    bool? normalizeVolume,
    bool? offlineCache,
    bool? matchTempo,
    bool? desktopWidget,
  }) => AppSettings(
    accentFromCover: accentFromCover ?? this.accentFromCover,
    accent: accent ?? this.accent,
    backdrop: backdrop ?? this.backdrop,
    backdropSpeed: backdropSpeed ?? this.backdropSpeed,
    backdropIntensity: backdropIntensity ?? this.backdropIntensity,
    font: font ?? this.font,
    lyricsSize: lyricsSize ?? this.lyricsSize,
    wavyProgress: wavyProgress ?? this.wavyProgress,
    glass: glass ?? this.glass,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    textScale: textScale ?? this.textScale,
    lyricsStyle: lyricsStyle ?? this.lyricsStyle,
    lyricsBlur: lyricsBlur ?? this.lyricsBlur,
    lyricsGlow: lyricsGlow ?? this.lyricsGlow,
    lyricsAlign: lyricsAlign ?? this.lyricsAlign,
    lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
    lyricsLift: lyricsLift ?? this.lyricsLift,
    depth3d: depth3d ?? this.depth3d,
    fadeSeconds: fadeSeconds ?? this.fadeSeconds,
    lyricsTranslate: lyricsTranslate ?? this.lyricsTranslate,
    notchIsland: notchIsland ?? this.notchIsland,
    skipIntros: skipIntros ?? this.skipIntros,
    normalizeVolume: normalizeVolume ?? this.normalizeVolume,
    offlineCache: offlineCache ?? this.offlineCache,
    matchTempo: matchTempo ?? this.matchTempo,
    desktopWidget: desktopWidget ?? this.desktopWidget,
  );

  Map<String, Object> toJson() => {
    'accentFromCover': accentFromCover,
    'accent': accent.toARGB32(),
    'backdrop': backdrop.name,
    'backdropSpeed': backdropSpeed,
    'backdropIntensity': backdropIntensity,
    'font': font,
    'lyricsSize': lyricsSize,
    'wavyProgress': wavyProgress,
    'glass': glass,
    'reduceMotion': reduceMotion,
    'textScale': textScale,
    'lyricsStyle': lyricsStyle.name,
    'lyricsBlur': lyricsBlur,
    'lyricsGlow': lyricsGlow,
    'lyricsAlign': lyricsAlign.name,
    'lyricsOffsetMs': lyricsOffsetMs,
    'lyricsLift': lyricsLift,
    'depth3d': depth3d,
    'fadeSeconds': fadeSeconds,
    'lyricsTranslate': lyricsTranslate,
    'notchIsland': notchIsland,
    'skipIntros': skipIntros,
    'normalizeVolume': normalizeVolume,
    'offlineCache': offlineCache,
    'matchTempo': matchTempo,
    'desktopWidget': desktopWidget,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    double num_(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    return AppSettings(
      accentFromCover: pick('accentFromCover', d.accentFromCover),
      accent: j['accent'] is int ? Color(j['accent'] as int) : d.accent,
      backdrop: BackdropStyle.values.asNameMap()[j['backdrop']] ?? d.backdrop,
      backdropSpeed: num_('backdropSpeed', d.backdropSpeed),
      backdropIntensity: num_('backdropIntensity', d.backdropIntensity),
      font: fonts.contains(j['font']) ? j['font'] as String : d.font,
      lyricsSize: num_('lyricsSize', d.lyricsSize),
      wavyProgress: pick('wavyProgress', d.wavyProgress),
      glass: pick('glass', d.glass),
      reduceMotion: pick('reduceMotion', d.reduceMotion),
      textScale: num_('textScale', d.textScale),
      lyricsStyle:
          LyricsStyle.values.asNameMap()[j['lyricsStyle']] ?? d.lyricsStyle,
      lyricsBlur: pick('lyricsBlur', d.lyricsBlur),
      lyricsGlow: num_('lyricsGlow', d.lyricsGlow),
      lyricsAlign:
          LyricsAlign.values.asNameMap()[j['lyricsAlign']] ?? d.lyricsAlign,
      lyricsOffsetMs:
          (j['lyricsOffsetMs'] as num?)?.round() ?? d.lyricsOffsetMs,
      lyricsLift: pick('lyricsLift', d.lyricsLift),
      depth3d: pick('depth3d', d.depth3d),
      fadeSeconds: num_('fadeSeconds', d.fadeSeconds),
      lyricsTranslate: pick('lyricsTranslate', d.lyricsTranslate),
      notchIsland: pick('notchIsland', d.notchIsland),
      skipIntros: pick('skipIntros', d.skipIntros),
      normalizeVolume: pick('normalizeVolume', d.normalizeVolume),
      offlineCache: pick('offlineCache', d.offlineCache),
      matchTempo: pick('matchTempo', d.matchTempo),
      desktopWidget: pick('desktopWidget', d.desktopWidget),
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'appearance';

  @override
  AppSettings build() {
    final raw = ref.read(libraryProvider).getMeta(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  void update(AppSettings Function(AppSettings s) change) {
    state = change(state);
    ref.read(libraryProvider).setMeta(_key, jsonEncode(state.toJson()));
  }

  void reset() => update((_) => const AppSettings());
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
