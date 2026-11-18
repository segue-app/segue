// Live check against Audius (network). Run: flutter test --tags live
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:segue/core/sources/audius_source.dart';

void main() {
  test('search finds songs and the stream is a seekable MP3', () async {
    final audius = AudiusSource();
    final found = await audius.search('dvrst phonk');
    expect(found, isNotEmpty);
    final info = await audius.resolveStream(found.first);
    final res = await http.Client().send(
      http.Request('GET', info.url)..headers['Range'] = 'bytes=0-99',
    );
    expect(res.statusCode, 206);
    expect(res.headers['content-type'], contains('audio'));
  });
}
