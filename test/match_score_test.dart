import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/match_source.dart';

Track _t(String artist, String title, int secs, {String id = 'x'}) => Track(
  id: id,
  source: SourceKind.youtube,
  title: title,
  artist: artist,
  duration: Duration(seconds: secs),
);

void main() {
  test('normalises and transliterates', () {
    expect(MatchSource.norm('Баста — Сансара!'), 'basta sansara');
    expect(MatchSource.norm('Кайф'), MatchSource.norm('Kayf'));
    expect(
      MatchSource.coreTitle('Bohemian Rhapsody - Remastered 2011'),
      'Bohemian Rhapsody',
    );
    expect(MatchSource.coreTitle('Космос (feat. Charusha)'), 'Космос');
  });

  test('ranks offline', () {
    final wanted = Track(
      id: 'w',
      source: SourceKind.match,
      title: 'Группа крови',
      artist: 'Кино',
      duration: const Duration(seconds: 284),
    );
    final r = MatchSource.rank(wanted, [
      (track: _t('Omnistar East', 'Kino - Gruppa Krovi / Кино - Группа Крови', 285, id: 'a'), official: false),
      (track: _t('Кино', 'Группа крови', 284, id: 'b'), official: true),
      (track: _t('Someone', 'Кино - Группа крови (cover)', 284, id: 'c'), official: false),
    ]);
    expect(r.first.track.id, 'b');
  });

  test('wants the version the import names, not another', () {
    final acoustic = Track(
      id: 'w',
      source: SourceKind.match,
      title: 'Птичка (Acoustic Version)',
      artist: 'HammAli & Navai',
      duration: const Duration(seconds: 205),
    );
    final found = [
      (track: _t('HammAli & Navai', 'HammAli & Navai - Птичка (Премьера клипа)', 201, id: 'clip'), official: true),
      (track: _t('HammAli & Navai', 'Птичка (Acoustic Version)', 205, id: 'ac'), official: true),
    ];
    expect(MatchSource.rank(acoustic, found).first.track.id, 'ac');
    final original = Track(
      id: 'o',
      source: SourceKind.match,
      title: 'Полковнику никто не пишет',
      artist: 'Би-2',
      duration: const Duration(seconds: 292),
    );
    expect(
      MatchSource.rank(original, [
        (track: _t('Би-2', 'Полковнику никто не пишет (Version 2024)', 295, id: 'new'), official: true),
        (track: _t('Fury 2', 'Би 2 - Полковнику никто не пишет', 295, id: 'old'), official: false),
      ]).first.track.id,
      'old',
    );
  });
}
