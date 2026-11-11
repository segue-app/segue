import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import 'deezer.dart';
import 'wave_settings.dart';

/// "Волна": endless radio built from Deezer's artist radios.
///
/// Artist wave: that artist and similar ones. My wave: a mix seeded by the
/// artists you like and listen to. Recently played tracks are skipped and
/// the queue refills itself as it runs out.
class Wave {
  Wave(this.catalog, this.library, this.player);

  final Catalog catalog;
  final LibraryStore library;

  /// Null in tests that only build batches.
  final SegueAudioHandler? player;
  final _rnd = Random();

  Set<String> _recent() => {
    for (final t in library.recentlyPlayed(limit: 200)) t.key,
  };

  /// Mixes several radios, interleaved, minus recently played tracks.
  Future<List<Track>> _mix(List<int> artistIds) async {
    final radios = await Future.wait(
      artistIds.map(
        (id) => catalog.artistRadio(id).catchError((Object _) => <Track>[]),
      ),
    );
    for (final r in radios) {
      r.shuffle(_rnd);
    }
    final recent = _recent();
    final seen = <String>{};
    final out = <Track>[];
    final longest = radios.fold(0, (m, r) => max(m, r.length));
    for (var i = 0; i < longest; i++) {
      for (final r in radios) {
        if (i < r.length && !recent.contains(r[i].key) && seen.add(r[i].key)) {
          out.add(r[i]);
        }
      }
    }
    return out;
  }

  /// Radio around one artist (from a track, the artist page…).
  Future<void> artistWave(Artist artist) async {
    final first = await _mix([artist.id]);
    if (first.isEmpty) throw StateError('Для «${artist.name}» волна пустая');
    await player!.playEndless(
      first,
      () => _mix([artist.id]),
      title: 'Волна: ${artist.name}',
    );
  }

  /// Radio from the artist of [track].
  Future<void> trackWave(Track track) async {
    final artist = await catalog.findArtist(track.artist);
    if (artist == null) {
      throw StateError('Не нашёл исполнителя «${track.artist}»');
    }
    await artistWave(artist);
  }

  /// Seeds: artists you like and play most, a few at random each time.
  Future<List<int>> _mySeeds({bool likedOnly = false}) async {
    final names = <String, int>{};
    for (final t in library.likedTracks().take(200)) {
      names[t.artist] = (names[t.artist] ?? 0) + 3;
    }
    if (!likedOnly) {
      for (final t in library.recentlyPlayed(limit: 100)) {
        names[t.artist] = (names[t.artist] ?? 0) + 1;
      }
    }
    final ranked = names.entries.where((e) => e.key.trim().isNotEmpty).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pool = ranked.take(12).map((e) => e.key).toList()..shuffle(_rnd);
    final ids = <int>[];
    for (final name in pool) {
      if (ids.length >= 4) break;
      final a = await catalog.findArtist(name).catchError((Object _) => null);
      if (a != null && !ids.contains(a.id)) ids.add(a.id);
    }
    return ids;
  }

  /// Personal endless mix, shaped by [settings] ("Настроить волну").
  /// With an empty library it starts from the charts.
  Future<void> myWave([WaveSettings settings = const WaveSettings()]) async {
    final first = await myWaveBatch(settings);
    if (first.isEmpty) throw StateError('Волна пустая');
    await player!.playEndless(
      first,
      () => myWaveBatch(settings),
      title: myWaveTitle,
    );
  }

  static const myWaveTitle = 'Моя волна';

  /// One portion of My wave. Exposed for tests.
  Future<List<Track>> myWaveBatch(WaveSettings settings) async {
    final instrumental = settings.language == 'Без слов';
    final themed = settings.activity != null || settings.mood != null;

    // Mood and activity come from public themed playlists; songs by
    // artists you already know go first so it still feels like yours.
    var mood = <Track>[];
    if (themed || instrumental) {
      mood = await _themed(settings);
      final known = _knownArtists();
      mood.shuffle(_rnd);
      mood.sort(
        (a, b) => (known.contains(_norm(b.artist)) ? 1 : 0).compareTo(
          known.contains(_norm(a.artist)) ? 1 : 0,
        ),
      );
    }
    // Instrumental music isn't in anyone's artist radio: themed only.
    final personal = instrumental ? <Track>[] : await _personal(settings);

    final mixed = mood.isEmpty
        ? personal
        : personal.isEmpty
        ? mood
        // Two themed tracks for every personal one.
        : _interleave([mood, personal], [2, 1]);

    final recent = settings.character == 'Любимое'
        ? {for (final t in library.recentlyPlayed(limit: 30)) t.key}
        : _recent();
    final seen = <String>{};
    final out = [
      for (final t in mixed)
        if (!recent.contains(t.key) &&
            seen.add(t.key) &&
            _languageOk(t, settings.language))
          t,
    ];
    if (out.isNotEmpty) return out;
    // Filters too narrow for what we found: better something than nothing.
    final chart = await catalog.chart(limit: 50)
      ..shuffle(_rnd);
    final fallback = [
      for (final t in chart)
        if (_languageOk(t, settings.language)) t,
    ];
    return fallback.isNotEmpty ? fallback : chart;
  }

  /// The personal part: artist radios, adjusted by "Характер".
  Future<List<Track>> _personal(WaveSettings settings) async {
    final likedOnly = settings.character == 'Любимое';
    final seeds = await _mySeeds(likedOnly: likedOnly);
    switch (settings.character) {
      case 'Любимое':
        // Your liked songs themselves, mixed with radios of their artists.
        final liked = library.likedTracks().toList()..shuffle(_rnd);
        final radio = seeds.isEmpty ? <Track>[] : await _mix(seeds);
        return _interleave([liked.take(40).toList(), radio], [1, 2]);
      case 'Незнакомое':
        // Artists similar to yours that you haven't been listening to.
        final known = _knownArtists();
        final related = <Artist>[];
        for (final id in seeds) {
          related.addAll(
            await catalog.related(id).catchError((Object _) => <Artist>[]),
          );
        }
        final fresh =
            related
                .where((a) => !known.contains(_norm(a.name)))
                .map((a) => a.id)
                .toSet()
                .toList()
              ..shuffle(_rnd);
        final ids = fresh.isEmpty ? seeds : fresh.take(4).toList();
        if (ids.isEmpty) return _chart();
        return [
          for (final t in await _mix(ids))
            if (!known.contains(_norm(t.artist))) t,
        ];
      case 'Популярное':
        // The biggest songs of your artists, plus the charts.
        final tops = await Future.wait(
          seeds.map(
            (id) => catalog
                .topTracks(id, limit: 10)
                .catchError((Object _) => <Track>[]),
          ),
        );
        for (final t in tops) {
          t.shuffle(_rnd);
        }
        return _interleave([...tops, await _chart()], null);
      default:
        return seeds.isEmpty ? _chart() : _mix(seeds);
    }
  }

  Future<List<Track>> _chart() async =>
      (await catalog.chart(limit: 50))..shuffle(_rnd);

  /// Search queries for themed playlists, in Russian and in English.
  static const _queries = <String, (String, String)>{
    'Просыпаюсь': ('утренняя музыка', 'morning acoustic'),
    'Тренируюсь': ('музыка для тренировок', 'workout'),
    'Работаю': ('музыка для работы', 'focus work'),
    'Отдыхаю': ('музыка для отдыха', 'chill relax'),
    'В дороге': ('музыка в дорогу', 'road trip'),
    'Засыпаю': ('музыка для сна', 'sleep'),
    'Бодрое': ('бодрая музыка', 'energy boost'),
    'Весёлое': ('весёлые песни', 'happy hits'),
    'Спокойное': ('спокойная музыка', 'calm chill'),
    'Грустное': ('грустные песни', 'sad songs'),
  };

  Future<List<Track>> _themed(WaveSettings s) async {
    final topics = [s.activity, s.mood].whereType<String>().toList();
    final queries = <String>[];
    if (s.language == 'Без слов') {
      queries.addAll(
        topics.isEmpty
            ? ['instrumental music', 'lofi beats']
            : topics.map((t) => 'instrumental ${_queries[t]!.$2}'),
      );
    } else {
      for (final t in topics) {
        final (ru, en) = _queries[t]!;
        if (s.language != 'Иностранный') queries.add(ru);
        if (s.language != 'Русский') queries.add(en);
      }
    }
    final lists = await Future.wait(
      queries.map(
        (q) => catalog.playlistsTracks(q).catchError((Object _) => <Track>[]),
      ),
    );
    for (final l in lists) {
      l.shuffle(_rnd);
    }
    return _interleave(lists, null);
  }

  static final _cyrillic = RegExp('[а-яёА-ЯЁ]');

  static bool _languageOk(Track t, String? language) => switch (language) {
    'Русский' => _cyrillic.hasMatch('${t.artist} ${t.title}'),
    'Иностранный' => !_cyrillic.hasMatch('${t.artist} ${t.title}'),
    _ => true,
  };

  static String _norm(String name) => name.toLowerCase().trim();

  /// Artists you like or have been listening to.
  Set<String> _knownArtists() => {
    for (final t in library.likedTracks()) _norm(t.artist),
    for (final t in library.recentlyPlayed(limit: 200)) _norm(t.artist),
  };

  /// Takes [weights] items from each list in turn (1 each by default).
  static List<Track> _interleave(List<List<Track>> lists, List<int>? weights) {
    final out = <Track>[];
    final pos = List.filled(lists.length, 0);
    var left = true;
    while (left) {
      left = false;
      for (var i = 0; i < lists.length; i++) {
        final take = weights?[i] ?? 1;
        for (var k = 0; k < take && pos[i] < lists[i].length; k++) {
          out.add(lists[i][pos[i]++]);
        }
        if (pos[i] < lists[i].length) left = true;
      }
    }
    return out;
  }
}

/// Created in main() and overridden there.
final waveProvider = Provider<Wave>(
  (ref) => throw UnimplementedError('waveProvider is overridden in main()'),
);
