// Runs the in-app network check from this machine (network required).
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/diag/net_check.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/youtube_source.dart';

void main() {
  test('net check', () async {
    final r = await NetCheck(
      sources: {
        SourceKind.youtube: YouTubeSource(),
        SourceKind.soundcloud: SoundCloudSource(),
      },
    ).run();
    for (final x in r) {
      print(x); // ignore: avoid_print
    }
    expect(r, hasLength(NetCheck.names.length));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
