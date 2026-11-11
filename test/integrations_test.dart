import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/integrations/discord.dart';
import 'package:segue/core/integrations/lastfm.dart';
import 'package:segue/core/integrations/updates.dart';

void main() {
  test('Last.fm signature: sorted name+value pairs, then the secret', () {
    // md5("api_keyKmethodauth.getMobileSessionpasswordPusernameUS")
    expect(
      LastFm.sign({
        'username': 'U',
        'password': 'P',
        'method': 'auth.getMobileSession',
        'api_key': 'K',
      }, 'S'),
      LastFm.sign({
        'api_key': 'K',
        'method': 'auth.getMobileSession',
        'password': 'P',
        'username': 'U',
      }, 'S'),
    );
    // md5("a1s")
    expect(LastFm.sign({'a': '1'}, 's'), 'f1e010a29298257bd7806020524fcfec');
  });

  test('version comparison', () {
    expect(isNewer('v0.2.0', '0.1.0'), isTrue);
    expect(isNewer('1.2.10', '1.2.9'), isTrue);
    expect(isNewer('0.1.0', '0.1.0'), isFalse);
    expect(isNewer('0.0.9', '0.1.0'), isFalse);
    expect(isNewer('1.0', '0.9.9'), isTrue);
  });

  test('Discord IPC frame and activity', () {
    final f = DiscordPresence.frame(1, {'a': 'б'});
    final len = f.buffer.asByteData().getInt32(4, Endian.little);
    expect(f.buffer.asByteData().getInt32(0, Endian.little), 1);
    expect(len, f.length - 8);
    final a = DiscordPresence.activity(
      title: 'Фея',
      artist: 'Miyagi',
      cover: 'https://x/y.jpg',
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 3),
      playing: true,
    );
    expect(a['type'], 2);
    final ts = a['timestamps'] as Map;
    expect(ts['end'] - ts['start'], 180000);
    expect((a['assets'] as Map)['large_image'], 'https://x/y.jpg');
  });
}
