// Live: Deezer catalogue (network). Run: flutter test --tags live
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/catalog/deezer.dart';
import 'package:segue/core/catalog/wave.dart';
import 'package:segue/core/catalog/wave_settings.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';

void main() {
  final c = Catalog();

  test('artist page: info, top tracks, albums, related', () async {
    final a = await c.findArtist('Miyagi & Andy Panda');
    expect(a, isNotNull);
    expect(a!.name.toLowerCase(), contains('miyagi'));
    final top = await c.topTracks(a.id);
    final albums = await c.albums(a.id, a.name);
    final related = await c.related(a.id);
    // ignore: avoid_print
    print(
      '${a.name}: ${a.fans} fans, ${top.length} top, ${albums.length} albums, '
      '${related.length} related; #1 ${top.first.title}',
    );
    expect(top.first.source, SourceKind.match);
    expect(top.first.artworkUrl, startsWith('https://'));
    expect(albums, isNotEmpty);
    final (album, tracks) = await c.album(albums.first.id);
    expect(tracks, isNotEmpty);
    expect(tracks.first.artworkUrl, album.cover);
  });

  test('radio is fresh and charts load', () async {
    final a = (await c.findArtist('Billie Eilish'))!;
    final r1 = await c.artistRadio(a.id);
    final r2 = await c.artistRadio(a.id);
    expect(r1, isNotEmpty);
    expect(r1.map((t) => t.key).join() != r2.map((t) => t.key).join(), isTrue);
    expect(await c.chart(genre: 116, limit: 10), hasLength(10));
  });

  test('my wave follows its filters', () async {
    final library = LibraryStore.memory();
    final c2 = Catalog();
    final liked = await c2.topTracks(
      (await c2.findArtist('Miyagi'))!.id,
      limit: 3,
    );
    for (final t in liked) {
      library.setLiked(t, true);
    }
    final wave = Wave(c2, library, null);
    final cyr = RegExp('[а-яёА-ЯЁ]');
    for (final s in const [
      WaveSettings(),
      WaveSettings(mood: 'Грустное', language: 'Русский'),
      WaveSettings(activity: 'Тренируюсь', language: 'Иностранный'),
      WaveSettings(character: 'Незнакомое'),
      WaveSettings(character: 'Любимое'),
      WaveSettings(character: 'Популярное'),
      WaveSettings(activity: 'Работаю', language: 'Без слов'),
    ]) {
      final batch = await wave.myWaveBatch(s);
      // ignore: avoid_print
      print(
        '${s.summary.isEmpty ? 'без фильтров' : s.summary}: ${batch.length} — '
        '${batch.take(4).map((t) => '${t.artist} – ${t.title}').join(' | ')}',
      );
      expect(batch, isNotEmpty);
      if (s.language == 'Русский') {
        expect(
          batch.every((t) => cyr.hasMatch('${t.artist} ${t.title}')),
          isTrue,
        );
      }
      if (s.character == 'Незнакомое') {
        expect(batch.any((t) => t.artist.toLowerCase() == 'miyagi'), isFalse);
      }
    }
    expect(
      WaveSettings.fromJson(
        const WaveSettings(mood: 'Бодрое', language: 'Русский').toJson(),
      ),
      const WaveSettings(mood: 'Бодрое', language: 'Русский'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
