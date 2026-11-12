import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/import/library_import.dart';
import 'package:segue/core/import/playlist_importer.dart';
import 'package:segue/core/library/library_store.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final importer = LibraryImporter(PlaylistImporter());

  test('Exportify CSVs: liked songs and playlists, quoted cells', () {
    const liked =
        '"Track URI","Track Name","Artist Name(s)","Album Name","Duration (ms)"\n'
        '"spotify:track:1","Фея","Miyagi, Эндшпиль","Hajime","224000"\n'
        '"spotify:track:2","Song, with comma","A ""quoted"" artist","X","180000"\n';
    const party = 'Track Name,Artist Name(s),Duration (ms)\nOne,Band,1000\n';
    final lib = importer.files([
      (name: 'Liked_Songs.csv', bytes: _b(liked)),
      (name: 'Party_Mix.csv', bytes: _b(party)),
    ]);
    expect(lib.liked.map((t) => '${t.artist} — ${t.title}'), [
      'Miyagi — Фея',
      'A "quoted" artist — Song, with comma',
    ]);
    expect(lib.liked.first.duration, const Duration(seconds: 224));
    expect(lib.playlists.single.name, 'Party Mix');
    expect(lib.playlists.single.tracks.single.title, 'One');
  });

  test('Spotify data export in a ZIP', () {
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'Spotify Account Data/YourLibrary.json',
          _b(
            jsonEncode({
              'tracks': [
                {
                  'artist': 'Miyagi',
                  'album': 'Hajime',
                  'track': 'Marlboro',
                  'uri': 'x',
                },
              ],
            }),
          ),
        ),
      )
      ..add(
        ArchiveFile.bytes(
          'Spotify Account Data/Playlist1.json',
          _b(
            jsonEncode({
              'playlists': [
                {
                  'name': 'Вечер',
                  'items': [
                    {
                      'track': {
                        'trackName': 'Kosandra',
                        'artistName': 'Miyagi',
                      },
                    },
                  ],
                },
              ],
            }),
          ),
        ),
      );
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final lib = importer.files([(name: 'my_spotify_data.zip', bytes: zip)]);
    expect(lib.liked.single.title, 'Marlboro');
    expect(lib.playlists.single.name, 'Вечер');
  });

  test('bulk likes keep the order and skip existing ones', () {
    final store = LibraryStore.memory();
    final lib = importer.files([
      (name: 'Liked.txt', bytes: _b('A - One\nB - Two\nC - Three\n')),
    ]);
    store.setLiked(lib.liked[1], true); // already liked before the import
    expect(store.likeMany(lib.liked), 2);
    expect(store.likedTracks().map((t) => t.title), ['Two', 'One', 'Three']);
  });

  test('yandex login from input', () {
    expect(LibraryImporter.yandexLogin('ivan.petrov'), 'ivan.petrov');
    expect(
      LibraryImporter.yandexLogin(
        'https://music.yandex.ru/users/ivan/playlists',
      ),
      'ivan',
    );
    expect(LibraryImporter.yandexLogin('not a login!'), isNull);
  });

  test(
    'a public Yandex profile, whole',
    () async {
      final lib = await importer.yandex('yandexmusic', maxPlaylists: 12);
      // ignore: avoid_print
      print(
        'yandexmusic: ${lib.liked.length} liked, ${lib.playlists.length} playlists',
      );
      expect(lib.liked, isNotEmpty);
      expect(lib.playlists, isNotEmpty);
    },
    tags: ['live'],
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('Exportify with URI and album-artist columns: names, not links', () {
    const csv =
        '"Track URI","Track Name","Album Name","Artist URI(s)",'
        '"Artist Name(s)","Album Artist Name(s)","Duration (ms)"\n'
        '"spotify:track:1","Cold Blood","Phonk","spotify:artist:0Psz",'
        '"Wilee, Someone","Various Artists","186000"\n';
    final t = LibraryImporter.csvTracks(csv).single;
    expect(t.title, 'Cold Blood');
    expect(t.artist, 'Wilee');
    expect(t.duration, const Duration(seconds: 186));
  });
}
