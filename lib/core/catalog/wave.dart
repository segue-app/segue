import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import '../models/track.dart';
import '../player/player_handler.dart';
import '../sources/youtube_source.dart';
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
  Wave(
    this.catalog,
    this.library,
    this.player, {
    Taste? taste,
    this.youtube,
    this.videoIdOf,
  }) : taste = taste ?? Taste(library);

  /// YouTube's mixes: what My wave and a song's radio are made of. Null
  /// (tests): Deezer's artist radios only.
  final YouTubeSource? youtube;

  /// The YouTube video a library song plays from, when known.
  final String? Function(Track t)? videoIdOf;

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
    bool steered = false,
  }) async {
    _offered
      ..clear()
      ..addAll(lead.map((t) => t.key));
    _resetSession(steered);
    _songs.addAll(lead.map(_songKey));
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
    if (youtube != null) {
      try {
        return await _steeredTrackWave(track);
      } catch (e) {
        debugPrint('wave ${track.title}: $e');
      }
    }
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
  /// A My wave restored from where it stopped (its queue already plays):
  /// it goes on refilling itself.
  void continueMyWave(WaveSettings settings) {
    final batch = _myWaveBatches(settings);
    if (batch == null) {
      player?.continueEndless(() => myWaveBatch(settings), myWaveTitle);
      return;
    }
    _offered.clear();
    _resetSession(true);
    player?.continueEndless(batch, myWaveTitle);
  }

  /// The steered portions of My wave for [settings]; null when those
  /// settings are Deezer's.
  Future<List<Track>> Function()? _myWaveBatches(WaveSettings settings) {
    final steer =
        youtube != null &&
        settings.activity == null &&
        settings.mood == null &&
        settings.language == null &&
        (settings.character == null || settings.character == 'Любимое');
    if (!steer) return null;
    final likedOnly = settings.character == 'Любимое';
    return () async {
      try {
        final b = await _steeredBatch(likedOnly: likedOnly);
        if (b.isNotEmpty) return b;
      } catch (e) {
        debugPrint('wave: $e');
      }
      // YouTube gave nothing (unreachable, nothing known yet): Deezer's.
      return myWaveBatch(settings);
    };
  }

  Future<void> myWave([WaveSettings settings = const WaveSettings()]) {
    // Plain My wave (or "Любимое"): YouTube's mixes of your songs, steered
    // by how you listen. Themes and the other characters: Deezer's.
    final batch = _myWaveBatches(settings);
    if (batch == null) return _play(() => myWaveBatch(settings), myWaveTitle);
    return _play(batch, myWaveTitle, steered: true);
  }

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

  // --- steered waves: YouTube mixes, re-ranked before every few songs ----

  /// Songs in one portion of a steered wave: few, so a skip or a like
  /// changes what comes within a song or two.
  static const steerSize = 5;

  bool _steered = false;

  /// Songs found and not offered yet; [pos]: where in its mix (0 is the
  /// song the mix was made from: the nearer, the more alike).
  final _pool = <({Track track, String seed, int pos})>[];

  /// Videos whose mix is already in the pool.
  final _mixed = <String>{};

  /// Videos to take mixes of next: songs liked or played through now.
  final _hot = <String>[];

  /// How this session feels about artists and mixes (skips, likes).
  final _now = <String, double>{};
  final _seedFeel = <String, double>{};
  final _fromSeed = <String, String>{};

  /// Songs offered, by name: one song uploaded by several channels
  /// comes once.
  final _songs = <String>{};

  /// Artists of the last songs offered, newest last.
  final _lastArtists = <String>[];

  int _quickSkips = 0;

  void _resetSession(bool steered) {
    _steered = steered;
    _pool.clear();
    _mixed.clear();
    _hot.clear();
    _now.clear();
    _seedFeel.clear();
    _fromSeed.clear();
    _songs.clear();
    _lastArtists.clear();
    _quickSkips = 0;
  }

  static final _dash = RegExp(r'\s[-–—]\s');
  static final _split = RegExp(
    r'\s*(,|&|\bfeat\.?|\bft\.?|\bx\b|\band\b|\bи\b)\s*',
    caseSensitive: false,
  );

  /// The main artist, from "Artist - Song" titles too (the channel is often
  /// a label).
  static String _artistKey(Track t) {
    final d = t.source == SourceKind.youtube ? _dash.firstMatch(t.title) : null;
    final who = d == null ? t.artist : t.title.substring(0, d.start);
    return _norm(who.split(_split).first);
  }

  /// The song itself, whoever uploaded it: artist and title without
  /// "(Official Video)", "| Lyrics" and the like.
  static String _songKey(Track t) {
    var title = t.title;
    final d = t.source == SourceKind.youtube ? _dash.firstMatch(title) : null;
    if (d != null) title = title.substring(d.end);
    title = title
        .replaceAll(RegExp(r'[(\[].*?[)\]]'), ' ')
        .split(RegExp(r'\s[|/]\s'))
        .first;
    final letters = RegExp(r'[^\p{L}\p{N}]', unicode: true);
    return '${_artistKey(t).replaceAll(letters, '')}|'
        '${title.toLowerCase().replaceAll(letters, '')}';
  }

  /// Hours of music, compilations, live streams: not a song.
  static final _notASong = RegExp(
    r'full album|playlist|сборник|подборк|\bhours?\b|\bчас(а|ов)?\b|non-?stop|'
    r'\bmix\s*20\d\d|top \d+|\blive stream|топ \d+',
    caseSensitive: false,
  );

  static bool _songLike(Track t) {
    final d = t.duration;
    if (d != null && (d.inSeconds < 60 || d.inMinutes >= 9)) return false;
    return !_notASong.hasMatch(t.title);
  }

  /// How you feel about the song's artist, all along (channel and name).
  double _feel(Track t) {
    final a = taste.artist(t.artist);
    final b = taste.artist(_artistKey(t));
    return a < 0 || b < 0 ? min(a, b) : max(a, b);
  }

  static const _seenFor = Duration(days: 10);

  /// Played in a wave lately: not offered again for a while.
  bool _seenLately(Track t) {
    final at = library.kvGet('wave_seen', t.key);
    return at is int &&
        DateTime.now().millisecondsSinceEpoch - at < _seenFor.inMilliseconds;
  }

  String? _videoOf(Track t) =>
      t.source == SourceKind.youtube ? t.id : videoIdOf?.call(t);

  /// Songs of yours to make mixes from: newer likes and songs you come
  /// back to most likely, artists you skip never.
  List<Track> _seedSongs({required bool likedOnly}) {
    final w = <String, ({Track t, double w})>{};
    void add(Track t, double weight) {
      if (_feel(t) < 0 || (_now[_artistKey(t)] ?? 0) < 0) return;
      final had = w[t.key];
      w[t.key] = (t: t, w: (had?.w ?? 0) + weight);
    }

    final liked = library.likedTracks();
    for (var i = 0; i < liked.length && i < 300; i++) {
      add(liked[i], 1 + 3 * exp(-i / 40));
    }
    if (!likedOnly) {
      final played = library.playedAtLeast(2, limit: 300);
      for (var i = 0; i < played.length; i++) {
        add(played[i], 0.5 + 1.5 * exp(-i / 80));
      }
    }
    // Weighted draw without putting back.
    final pool = w.values.toList();
    final out = <Track>[];
    while (pool.isNotEmpty && out.length < 12) {
      final total = pool.fold(0.0, (a, b) => a + b.w);
      var r = _rnd.nextDouble() * total;
      var i = pool.indexWhere((e) => (r -= e.w) <= 0);
      if (i < 0) i = pool.length - 1;
      out.add(pool.removeAt(i).t);
    }
    return out;
  }

  /// Adds the mixes of [count] songs to the pool: songs just liked or
  /// played through first, then songs of yours.
  Future<void> _grow(int count, {bool likedOnly = false}) async {
    final ids = <String>[];
    while (_hot.isNotEmpty && ids.length < count) {
      final id = _hot.removeAt(0);
      if (_mixed.add(id)) ids.add(id);
    }
    if (ids.length < count) {
      Track? unknown;
      for (final t in _seedSongs(likedOnly: likedOnly)) {
        if (ids.length >= count) break;
        final id = _videoOf(t);
        if (id == null) {
          unknown ??= t;
        } else if (_mixed.add(id)) {
          ids.add(id);
        }
      }
      // Songs from SoundCloud or never played yet: found on YouTube.
      if (ids.isEmpty && unknown != null) {
        final found = await youtube!
            .searchDetailed('${unknown.artist} ${unknown.title}', limit: 1)
            .catchError((Object _) => <({Track track, bool official})>[]);
        if (found.isNotEmpty && _mixed.add(found.first.track.id)) {
          ids.add(found.first.track.id);
        }
      }
    }
    if (ids.isEmpty) return;
    final mixes = await Future.wait(
      ids.map((id) => youtube!.mix(id).catchError((Object _) => <Track>[])),
    );
    for (var i = 0; i < ids.length; i++) {
      final mix = mixes[i];
      for (var pos = 0; pos < mix.length; pos++) {
        final t = mix[pos];
        if (!_songLike(t) || _fromSeed.containsKey(t.key)) continue;
        _fromSeed[t.key] = ids[i];
        _pool.add((track: t, seed: ids[i], pos: pos));
      }
    }
  }

  /// One portion of the steered My wave (tests).
  @visibleForTesting
  Future<List<Track>> steeredBatch({bool likedOnly = false}) {
    _steered = true;
    return _steeredBatch(likedOnly: likedOnly);
  }

  /// The next few songs of a steered wave, ranked as of now.
  Future<List<Track>> _steeredBatch({
    bool likedOnly = false,
    int size = steerSize,
  }) async {
    final recentSongs = library.recentlyPlayed(limit: 250);
    final recent = {for (final t in recentSongs) t.key, ..._offered};
    final recentNames = {for (final t in recentSongs) _songKey(t), ..._songs};
    bool fresh(Track t) =>
        !recent.contains(t.key) &&
        !recentNames.contains(_songKey(t)) &&
        !taste.isDisliked(t) &&
        _feel(t) > -4 &&
        (_now[_artistKey(t)] ?? 0) > -2 &&
        !_seenLately(t);

    _pool.removeWhere((c) => !fresh(c.track));
    for (var round = 0; round < 3 && _pool.length < 25; round++) {
      final before = _pool.length;
      await _grow(_pool.isEmpty ? 3 : 2, likedOnly: likedOnly);
      _pool.removeWhere((c) => !fresh(c.track));
      if (_pool.length == before && _hot.isEmpty) break;
    }

    double score(({Track track, String seed, int pos}) c) =>
        1.5 * (1 - c.pos / 30).clamp(0.0, 1.0) +
        (_seedFeel[c.seed] ?? 0) +
        (_now[_artistKey(c.track)] ?? 0) +
        _feel(c.track).clamp(-4.0, 6.0) * 0.25 +
        _rnd.nextDouble() * 1.2;
    final scored = {for (final c in _pool) c.track.key: score(c)};
    final ranked = [..._pool]
      ..sort((a, b) => scored[b.track.key]!.compareTo(scored[a.track.key]!));

    // Your own songs now and then, as Yandex's wave does.
    final own = _familiar().where(fresh).toList();
    final out = <Track>[];
    bool fits(Track t) {
      final a = _artistKey(t);
      final near = _lastArtists.length < 4
          ? _lastArtists
          : _lastArtists.sublist(_lastArtists.length - 4);
      if (near.contains(a)) return false;
      final window = _lastArtists.length < 15
          ? _lastArtists
          : _lastArtists.sublist(_lastArtists.length - 15);
      return window.where((x) => x == a).length < 2;
    }

    void place(Track t) {
      out.add(t);
      _offered.add(t.key);
      _songs.add(_songKey(t));
      _lastArtists.add(_artistKey(t));
      if (_lastArtists.length > 30) _lastArtists.removeAt(0);
    }

    final wantOwn = likedOnly ? 2 : (_rnd.nextDouble() < 0.6 ? 1 : 0);
    var ownLeft = wantOwn;
    for (final c in ranked) {
      if (out.length >= size) break;
      final t = c.track;
      if (ownLeft > 0 && out.isNotEmpty && _rnd.nextDouble() < 0.4) {
        final i = own.indexWhere(fits);
        if (i >= 0) {
          place(own.removeAt(i));
          ownLeft--;
          if (out.length >= size) break;
        }
      }
      if (_songs.contains(_songKey(t)) || !fits(t)) continue;
      place(t);
    }
    _pool.removeWhere((c) => _offered.contains(c.track.key));
    // Too few artists to space them out: closer is better than nothing.
    if (out.length < size) {
      for (final c in ranked) {
        if (out.length >= size) break;
        if (_offered.contains(c.track.key) || _songs.contains(_songKey(c.track))) {
          continue;
        }
        place(c.track);
      }
      _pool.removeWhere((c) => _offered.contains(c.track.key));
    }
    return out;
  }

  /// Radio from one song: its own mix first, then mixes of the songs you
  /// like in it.
  Future<void> _steeredTrackWave(Track track) async {
    var id = _videoOf(track);
    if (id == null) {
      final found = await youtube!.searchDetailed(
        '${track.artist} ${track.title}',
        limit: 1,
      );
      if (found.isEmpty) throw StateError('not on YouTube');
      id = found.first.track.id;
    }
    final seed = id;
    var first = true;
    Future<List<Track>> batch() async {
      if (first) {
        first = false;
        _hot.add(seed);
        _seedFeel[seed] = 1.5;
      } else if (_hot.isEmpty && _pool.length < 25) {
        // The radio keeps to this song's world: more of its mix's songs.
        final near = _pool.where((c) => c.seed == seed && c.pos < 12).toList()
          ..shuffle(_rnd);
        for (final c in near.take(2)) {
          if (!_mixed.contains(c.track.id)) _hot.add(c.track.id);
        }
      }
      return _steeredBatch();
    }

    await _play(
      batch,
      'Радио: {0}'.trArgs([track.title]),
      lead: [track],
      steered: true,
    );
  }

  bool get _active => _steered && player?.waveTitle.value != null;

  /// How a wave song was left: steers what comes next at once.
  void heard(Track t, Duration played, Duration? length, bool skipped) {
    if (!_active) return;
    library.kvPut(
      'wave_seen',
      t.key,
      DateTime.now().millisecondsSinceEpoch,
      keep: 4000,
    );
    final a = _artistKey(t);
    final seed = _fromSeed[t.key];
    final fraction = length == null || length.inMilliseconds <= 0
        ? null
        : played.inMilliseconds / length.inMilliseconds;
    final quick =
        skipped &&
        played < const Duration(seconds: 30) &&
        (fraction == null || fraction < 0.3);
    if (quick) {
      _quickSkips++;
      _now[a] = (_now[a] ?? 0) - 1.5;
      if (seed != null) {
        _seedFeel[seed] = (_seedFeel[seed] ?? 0) - 0.6;
        if (_seedFeel[seed]! <= -1.2) _pool.removeWhere((c) => c.seed == seed);
      }
      // That artist leaves the queue now; after two skips in a row the
      // rest of it is picked anew.
      player?.removeUpcomingWhere(
        (x) =>
            _offered.contains(x.key) &&
            (_quickSkips >= 2 || _artistKey(x) == a),
        keep: _quickSkips >= 2 ? 1 : 0,
      );
      if (_quickSkips >= 2) _quickSkips = 0;
      return;
    }
    _quickSkips = 0;
    if (!skipped || (fraction != null && fraction > 0.7)) {
      _now[a] = (_now[a] ?? 0) + 0.6;
      if (seed != null) _seedFeel[seed] = (_seedFeel[seed] ?? 0) + 0.3;
      final id = _videoOf(t);
      if (id != null && !_mixed.contains(id) && _hot.length < 3) _hot.add(id);
    }
  }

  /// "Открытия недели": songs by artists you've never played, from the
  /// mixes of your songs. Put together again once a week.
  Future<void> refreshDiscoveries({bool force = false}) async {
    if (youtube == null) return;
    final at = library.discoveriesAt();
    if (!force &&
        at != null &&
        DateTime.now().difference(at) < const Duration(days: 7)) {
      return;
    }
    final known = <String>{
      for (final a in library.topArtists(days: 3650, limit: 5000))
        _norm(a.artist),
    };
    bool isNew(Track t) =>
        !known.contains(_artistKey(t)) &&
        !known.contains(_norm(t.artist)) &&
        _feel(t) >= 0 &&
        !taste.isDisliked(t) &&
        _songLike(t);
    final seeds = _seedSongs(likedOnly: false);
    final ids = <String>[];
    for (final t in seeds) {
      if (ids.length >= 10) break;
      final id = _videoOf(t);
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    if (ids.isEmpty) return;
    final mixes = await Future.wait(
      ids.map((id) => youtube!.mix(id).catchError((Object _) => <Track>[])),
    );
    // Round-robin over the mixes, two songs per new artist at most. Only
    // the start of a mix: further on it drifts to whatever is popular.
    final out = <Track>[];
    final perArtist = <String, int>{};
    final names = <String>{};
    for (var pos = 0; pos < 10 && out.length < 30; pos++) {
      for (final mix in mixes) {
        if (pos >= mix.length || out.length >= 30) continue;
        final t = mix[pos];
        final a = _artistKey(t);
        if (!isNew(t) || (perArtist[a] ?? 0) >= 2 || !names.add(_songKey(t))) {
          continue;
        }
        perArtist[a] = (perArtist[a] ?? 0) + 1;
        out.add(t);
      }
    }
    if (out.length >= 5) library.setDiscoveries(out);
  }

  /// A song liked while its wave plays: more like it, from the next song.
  Future<void> liked(Track t) async {
    if (!_active) return;
    final a = _artistKey(t);
    _now[a] = (_now[a] ?? 0) + 1.5;
    final id = _videoOf(t);
    if (id == null || _mixed.contains(id)) return;
    _hot.insert(0, id);
    _seedFeel[id] = 1.5;
    await _grow(1);
    player?.removeUpcomingWhere((x) => _offered.contains(x.key), keep: 1);
  }
}

/// Created in main() and overridden there.
final waveProvider = Provider<Wave>(
  (ref) => throw UnimplementedError('waveProvider is overridden in main()'),
);
