import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Настроить волну", as in Yandex Music: what you're doing, what kind of
/// music, the mood and the language. Each is optional (null = any).
class WaveSettings {
  const WaveSettings({this.activity, this.character, this.mood, this.language});

  final String? activity;
  final String? character;
  final String? mood;
  final String? language;

  static const activities = [
    'Просыпаюсь',
    'Тренируюсь',
    'Работаю',
    'Отдыхаю',
    'В дороге',
    'Засыпаю',
  ];
  static const characters = ['Любимое', 'Незнакомое', 'Популярное'];
  static const moods = ['Бодрое', 'Весёлое', 'Спокойное', 'Грустное'];
  static const languages = ['Русский', 'Иностранный', 'Без слов'];

  bool get isEmpty =>
      activity == null && character == null && mood == null && language == null;

  /// "Тренируюсь · Бодрое" for the card; empty when nothing is set.
  String get summary => [
    activity,
    character,
    mood,
    language,
  ].whereType<String>().map((s) => s.tr).join(' · ');

  WaveSettings copyWith({
    String? Function()? activity,
    String? Function()? character,
    String? Function()? mood,
    String? Function()? language,
  }) => WaveSettings(
    activity: activity == null ? this.activity : activity(),
    character: character == null ? this.character : character(),
    mood: mood == null ? this.mood : mood(),
    language: language == null ? this.language : language(),
  );

  Map<String, dynamic> toJson() => {
    'activity': activity,
    'character': character,
    'mood': mood,
    'language': language,
  };

  factory WaveSettings.fromJson(Map<String, dynamic> j) {
    String? pick(String key, List<String> allowed) {
      final v = j[key];
      return allowed.contains(v) ? v as String : null;
    }

    return WaveSettings(
      activity: pick('activity', activities),
      character: pick('character', characters),
      mood: pick('mood', moods),
      language: pick('language', languages),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WaveSettings && jsonEncode(other) == jsonEncode(this);

  @override
  int get hashCode => jsonEncode(this).hashCode;
}

class WaveSettingsNotifier extends Notifier<WaveSettings> {
  static const _key = 'wave_settings';

  @override
  WaveSettings build() {
    final raw = ref.read(libraryProvider).getMeta(_key);
    if (raw == null) return const WaveSettings();
    try {
      return WaveSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const WaveSettings();
    }
  }

  void set(WaveSettings value) {
    state = value;
    ref.read(libraryProvider).setMeta(_key, jsonEncode(value.toJson()));
  }
}

final waveSettingsProvider =
    NotifierProvider<WaveSettingsNotifier, WaveSettings>(
      WaveSettingsNotifier.new,
    );
