import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/audius_source.dart';

void main() {
  const song = Track(
    id: 'ab39rE',
    source: SourceKind.audius,
    title: 'Komarovo (DVRST phonk remix)',
    artist: 'Kristers',
    duration: Duration(seconds: 146),
  );

  test('an Audius song reads back as itself', () {
    final back = Track.fromJson(song.toJson());
    expect(back.source, SourceKind.audius);
    expect(back.key, 'audius:ab39rE');
    expect(back.title, song.title);
  });

  test('older Segue versions see a song to match by title', () {
    final j = song.toJson();
    // What 0.3.28 and older read: only "source", which they know.
    expect(j['source'], 'match');
    expect(SourceKind.values.map((k) => k.name), contains(j['source']));
    // Old songs are written exactly as before.
    const yt = Track(
      id: 'x',
      source: SourceKind.youtube,
      title: 't',
      artist: 'a',
    );
    expect(yt.toJson()['source'], 'youtube');
    expect(yt.toJson().containsKey('kind'), isFalse);
  });

  test('a source from a newer Segue becomes a matched song', () {
    final t = Track.fromJson({
      'id': '42',
      'source': 'match',
      'kind': 'somethingNew',
      'title': 'Song',
      'artist': 'Artist',
    });
    expect(t.source, SourceKind.match);
    expect(t.title, 'Song');
  });

  test('search keeps playable songs and reads cover and length', () async {
    final source = AudiusSource(
      client: MockClient((req) async {
        expect(req.url.queryParameters['app_name'], 'segue');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'data': [
                {
                  'id': 'ab39rE',
                  'title': ' Komarovo ',
                  'duration': 146,
                  'is_streamable': true,
                  'artwork': {'480x480': 'https://a/480.jpg'},
                  'user': {'name': 'Kristers', 'handle': 'kristers'},
                },
                {'id': 'gone', 'title': 'Gone', 'is_streamable': false},
              ],
            }),
          ),
          200,
        );
      }),
    );
    final found = await source.search('komarovo');
    expect(found, hasLength(1));
    expect(found.first.title, 'Komarovo');
    expect(found.first.artist, 'Kristers');
    expect(found.first.artworkUrl, 'https://a/480.jpg');
    expect(found.first.duration, const Duration(seconds: 146));
  });
}
