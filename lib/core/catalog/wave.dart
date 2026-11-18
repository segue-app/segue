import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import 'deezer.dart';
import 'taste.dart';
import 'wave_settings.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Волна": endless radio built from Deezer's artist radios.
///
/// Artist wave: that artist and similar ones. My wave: a mix seeded by the
/// artists you like and listen to. Recently played tracks are skipped and
/// the queue refills itself as it runs out.
class Wave {
  Wave(this.catalog, this.library, this.player, {Taste? taste})
    : taste = taste ?? Taste(library);

  final Catalog catalog;
  final LibraryStore library;

  /// What you like, learnt from listening (skips, songs played through).
  final Taste taste;

  /// Null in tests that only build batches.
  final SegueAudioHandler? player;
  final _rnd = Random();

  /// Songs in one portion of a wave: small, so what you skip or like
  /// shapes the next portion soon, not hours later.
  static const batchSize = 30;

  /// Songs this wave has already offered: later portions don't repeat
  /// them, even ones skipped before they were recorded as played.
  final _offered = <String>{};

  /// The artists the last few portions were built around.
  final _centres = <String>[];

  /// Recently played songs and the ones this wave has already offered.
  Set<String> _recent() => {
    for (final t in library.recentlyPlayed(limit: 250)) t.key,
    ..._offered,
  };

  /// Mixes several radios, interleaved, minus recently played tracks.
  /// [weights]: how many songs each radio gives per turn (1 each).
  Future<List<Track>> _mix(List<int> artistIds, [List<int>? weights]) async {
    final radios = await Future.wait(
      artistIds.map(
        (id) => catalog.artistRadio(id).catchError((Object _) => <Track>[]),
      ),
    );
    final recent = _recent();
    for (final r in radios) {
      r.shuffle(_rnd);
      r.removeWhere((t) => recent.contains(t.key));
    }
    final seen = <String>{};
    return [
      for (final t in _interleave(radios, weights))
        if (seen.add(t.key)) t,
    ];
  }

  /// The portion as it will play: your taste orders it, then no artist
  /// more than [perArtist] times and never twice within a few songs.
  /// What it keeps counts as offered.
  List<Track> _finish(List<Track> tracks, {int perArtist = 3}) {
    final ordered = taste.order(tracks, _rnd);
    final out = <Track>[];
    final count = <String, int>{};
    final waiting = <Track>[];
    bool fits(Track t) {
      final a = _norm(t.artist);
      if ((count[a] ?? 0) >= perArtist) return false;
      final near = out.length < 3 ? out : out.sublist(out.length - 3);
      return !near.any((n) => _norm(n.artist) == a);
    }

    void place(Track t) {
      out.add(t);
      final a = _norm(t.artist);
      count[a] = (count[a] ?? 0) + 1;
    }

    for (final t in ordered) {
      if (out.length >= batchSize) break;
      // A song held back for spacing goes in as soon as it fits.
      final ready = waiting.indexWhere(fits);
      if (ready >= 0) place(waiting.removeAt(ready));
      if (out.length >= batchSize) break;
      if (fits(t)) {
        place(t);
      } else if ((count[_norm(t.artist)] ?? 0) < perArtist) {
        waiting.add(t);
      }
    }
    // Few artists to go round: better a little closer than too short.
    for (final t in waiting) {
      if (out.length >= batchSize) break;
      if ((count[_norm(t.artist)] ?? 0) < perArtist) place(t);
    }
    _offered.addAll(out.map((t) => t.key));
    return out;
  }

  /// Starts an endless wave: [batch] makes each portion.
  Future<void> _play(
    Future<List<Track>> Function() batch,
    String title, {
    List<Track> lead = const [],
  }) async {
    _offered
      ..clear()
      ..addAll(lead.map((t) => t.key));
    final first = await batch();
    if (first.isEmpty) throw StateError('Волна пустая'.tr);
    await player!.playEndless([...lead, ...first], batch, title: title);
  }

  /// Radio around one artist (from a track, the artist page…).
  Future<void> artistWave(Artist artist) async {
    Future<List<Track>> batch() async =>
        _finish(await _mix([artist.id]), perArtist: 8);
    try {
      await _play(batch, 'Волна: {0}'.trArgs([artist.name]));
    } on StateError {
      throw StateError('Для «{0}» волна пустая'.trArgs([artist.name]));
    }
  }

  /// Radio from one song: the song itself first, then its artist and
  /// artists like them. The similar artists are picked anew for each batch,
  /// so the radio keeps moving instead of circling one artist.
  Future<void> trackWave(Track track) async {
    final artist = await catalog.findArtist(track.artist, strict: true);
    if (artist == null) {
      throw StateError('Не нашёл исполнителя «{0}»'.trArgs([track.artist]));
    }
    final related = await catalog
        .related(artist.id)
        .catchError((Object _) => <Artist>[]);
    Future<List<Track>> batch() {
      final pick = [...related]..shuffle(_rnd);
      return _mix([artist.id, ...pick.take(3).map((a) => a.id)]);
    }

    final same = _sameSong(track);
    Future<List<Track>> next() async => _finish([
      for (final t in await batch())
        if (!same(t)) t,
    ], perArtist: 5);
    try {
      await _play(next, 'Радио: {0}'.trArgs([track.title]), lead: [track]);
    } on StateError {
      throw StateError('Для «{0}» волна пустая'.trArgs([track.title]));
    }
  }

  /// Whether a catalog track is [track] (ids differ between sources).
  static bool Function(Track) _sameSong(Track track) {
    String k(Track t) =>
        '${_norm(t.artist)}|${_norm(t.title).replaceAll(RegExp(r'\s*[(\[].*$'), '')}';
    final key = k(track);
    return (t) => t.key == track.key || k(t) == key;
  }

  /// Seeds for a portion: artists drawn at random, more likely the more
  /// you've been playing and liking them lately. The first is the
  /// portion's centre; the others are kept only if they sound like it
  /// (Deezer counts them as similar), so film scores don't land between
  /// rap songs. Artists Deezer doesn't know by that exact name are left
  /// out: their own songs come in through [_familiar].
  Future<List<int>> _mySeeds({bool likedOnly = false}) async {
    final names = <String, double>{};
    void add(String artist, double w) {
      final k = artist.trim();
      if (k.isNotEmpty) names[k] = (names[k] ?? 0) + w;
    }

    final liked = library.likedTracks();
    for (var i = 0; i < liked.length && i < 200; i++) {
      add(liked[i].artist, 2 + 3 * exp(-i / 40)); // newer likes count more
    }
    if (!likedOnly) {
      // Songs you came back to, not everything a radio once started.
      final played = library.playedAtLeast(2, limit: 300);
      for (var i = 0; i < played.length; i++) {
        add(played[i].artist, 2 * exp(-i / 80));
      }
      for (final a in taste.favourites()) {
        add(a, 3);
      }
    }
    final weights = <String, double>{};
    names.forEach((name, w) {
      final feel = taste.artist(name);
      if (feel <= -3) return;
      // The last portions' centres step aside, so each portion has a new one.
      final rest = _centres.contains(_norm(name)) ? 0.15 : 1.0;
      weights[name] = max(0.2, w + feel.clamp(-3, 6)) * rest;
    });

    // Weighted draw, without putting anyone back, among the artists you
    // listen to most: one song played twice doesn't make a centre.
    final top = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final order = <String>[];
    final pool = {for (final e in top.take(15)) e.key: e.value};
    while (pool.isNotEmpty && order.length < 10) {
      final total = pool.values.fold(0.0, (a, b) => a + b);
      var r = _rnd.nextDouble() * total;
      final pick = pool.keys.firstWhere(
        (k) => (r -= pool[k]!) <= 0,
        orElse: () => pool.keys.last,
      );
      order.add(pick);
      pool.remove(pick);
    }

    final ids = <int>[];
    Set<int>? around; // the centre and the artists like it
    for (final name in order) {
      if (ids.length >= 4) break;
      final a = await catalog
          .findArtist(name, strict: true)
          .catchError((Object _) => null);
      if (a == null || ids.contains(a.id)) continue;
      final rel = await catalog
          .related(a.id)
          .catchError((Object _) => <Artist>[]);
      final mine = {a.id, ...rel.map((r) => r.id)};
      if (around == null) {
        around = mine;
        ids.add(a.id);
        _centres
          ..add(_norm(name))
          ..removeRange(0, max(0, _centres.length - 3));
      } else if (mine.any(around.contains)) {
        ids.add(a.id);
      }
    }
    return ids;
  }

  /// Your own songs you haven't heard for a while, from artists you
  /// don't skip: what the catalog can't offer for artists it doesn't know.
  List<Track> _familiar() {
    final recent = _recent();
    final seen = <String>{};
    final out = [
      for (final t in [
        ...library.likedTracks(),
        ...library.playedAtLeast(2, limit: 1500),
      ])
        if (!recent.contains(t.key) &&
            t.source != SourceKind.local &&
            taste.artist(t.artist) >= 0 &&
            seen.add(t.key))
          t,
    ];
    return out..shuffle(_rnd);
  }

  /// Personal endless mix, shaped by [settings] ("Настроить волну").
  /// With an empty library it starts from the charts.
  Future<void> myWave([WaveSettings settings = const WaveSettings()]) =>
      _play(() => myWaveBatch(settings), myWaveTitle);

  static const myWaveTitle = 'Моя волна';

  /// Radio of a genre, one tap: what's popular in it here and radios of
  /// its artists, a fresh set of artists for each portion.
  Future<void> genreWave(int genre, String name) async {
    Future<List<Track>> batch() async {
      final chart = await catalog.chart(genre: genre, limit: 50);
      final names = <String>[];
      for (final t in chart) {
        if (t.artist.trim().isNotEmpty && !names.contains(t.artist)) {
          names.add(t.artist);
        }
      }
      names.shuffle(_rnd);
      final ids = <int>[];
      for (final n in names.take(10)) {
        if (ids.length >= 4) break;
        final a = await catalog.findArtist(n).catchError((Object _) => null);
        if (a != null && !ids.contains(a.id)) ids.add(a.id);
      }
      final radio = ids.isEmpty ? <Track>[] : await _mix(ids);
      chart.shuffle(_rnd);
      final recent = _recent();
      final seen = <String>{};
      return _finish([
        for (final t in _interleave([radio, chart], [2, 1]))
          if (!recent.contains(t.key) && seen.add(t.key)) t,
      ]);
    }

    await _play(batch, 'Радио: {0}'.trArgs([name]));
  }

  /// Radio of a mood (Бодрое, Спокойное…), shaped by your taste.
  Future<void> moodWave(String mood) async {
    final settings = WaveSettings(mood: mood);
    await _play(() => myWaveBatch(settings), 'Радио: {0}'.trArgs([mood.tr]));
  }

  /// One portion of My wave. Exposed for tests.
  Future<List<Track>> myWaveBatch(WaveSettings settings) async {
    final instrumental = settings.language == 'Без слов';
    final themed = settings.activity != null || settings.mood != null;

    // Your seeds, also used to tell which themed songs are near your taste.
    final likedOnly = settings.character == 'Любимое';
    final seeds = instrumental ? <int>[] : await _mySeeds(likedOnly: likedOnly);

    // Mood and activity come from public themed playlists. Songs by
    // artists you know go first, then by artists like yours; few of each
    // artist, so one playlist's favourite doesn't take over.
    var mood = <Track>[];
    if (themed || instrumental) {
      mood = await _themed(settings);
      final known = _knownArtists();
      final near = <String>{};
      for (final id in seeds) {
        for (final a
            in await catalog.related(id).catchError((Object _) => <Artist>[])) {
          near.add(_norm(a.name));
        }
      }
      int rank(Track t) {
        final a = _norm(t.artist);
        return known.contains(a)
            ? 0
            : near.contains(a)
            ? 1
            : 2;
      }

      mood.shuffle(_rnd);
      mood.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    // Instrumental music isn't in anyone's artist radio: themed only.
    final personal = instrumental
        ? <Track>[]
        : await _personal(settings, seeds);

    final mixed = mood.isEmpty
        ? personal
        : personal.isEmpty
        ? mood
        : _interleave([mood, personal], [1, 1]);

    final recent = likedOnly
        ? {
            for (final t in library.recentlyPlayed(limit: 30)) t.key,
            ..._offered,
          }
        : _recent();
    final seen = <String>{};
    final out = [
      for (final t in mixed)
        if (!recent.contains(t.key) &&
            seen.add(t.key) &&
            _languageOk(t, settings.language))
          t,
    ];
    final portion = _finish(out, perArtist: themed ? 2 : 3);
    if (portion.isNotEmpty) return portion;
    // Filters too narrow for what we found: better something than nothing.
    final chart = await catalog.chart(limit: 50)
      ..shuffle(_rnd);
    final fallback = [
      for (final t in chart)
        if (_languageOk(t, settings.language)) t,
    ];
    return _finish(fallback.isNotEmpty ? fallback : chart);
  }

  /// The personal part: artist radios, adjusted by "Характер".
  Future<List<Track>> _personal(WaveSettings settings, List<int> seeds) async {
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
        // Around the centre artist (twice as much of its radio), with a
        // quarter of your own songs you haven't heard for a while.
        final radio = seeds.isEmpty
            ? await _chart()
            : await _mix(seeds, [2, for (var i = 1; i < seeds.length; i++) 1]);
        return _interleave([radio, _familiar()], [3, 1]);
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
