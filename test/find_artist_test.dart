import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:segue/core/catalog/deezer.dart';

void main() {
  // Deezer's artist search answers with its best guesses, by name.
  Catalog deezer(List<String> names) => Catalog(
    client: MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'data': [
              for (var i = 0; i < names.length; i++)
                {'id': i + 1, 'name': names[i], 'nb_fan': 100 - i},
            ],
          }),
        ),
        200,
      ),
    ),
  );

  test('strict search refuses someone else with a similar name', () async {
    final c = deezer(['To Van Kao', 'Toga']);
    expect(await c.findArtist('TOGANAKO', strict: true), isNull);
    // Elsewhere (opening an artist page) the best guess is still fine.
    expect((await c.findArtist('TOGANAKO'))?.name, 'To Van Kao');
  });

  test('case, spaces and punctuation don\'t matter', () async {
    final c = deezer(['Ndoff', 'Айскрин', 'nyan.mp3']);
    expect((await c.findArtist('айскрин', strict: true))?.name, 'Айскрин');
    expect((await c.findArtist('NYAN MP3', strict: true))?.name, 'nyan.mp3');
    expect(await c.findArtist('mdofa', strict: true), isNull);
  });
}
