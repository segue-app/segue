
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sync/sync_service.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: 'Song $id', artist: 'A');

void main() {
  // No TestWidgetsFlutterBinding here: it replaces real HTTP with a stub
  // that answers 400, and these tests talk to real local servers.
  late SyncService laptop, phone;
  late FakePlayer laptopPlayer, phonePlayer;

  setUp(() async {
    laptopPlayer = FakePlayer();
    phonePlayer = FakePlayer();
    laptop = SyncService(
      library: LibraryStore.memory(),
      player: laptopPlayer,
      enableDiscovery: false,
    );
    phone = SyncService(
      library: LibraryStore.memory(),
      player: phonePlayer,
      enableDiscovery: false,
    );
    await laptop.start();
    await phone.start();
  });

  tearDown(() async {
    await laptop.dispose();
    await phone.dispose();
  });

  Future<void> pairDevices() async {
    final code = laptop.openPairing();
    final dev = await phone.probe('127.0.0.1', laptop.port);
    await phone.pair(dev, code);
    // The laptop learns the phone's address from the pairing request.
    await laptop.probe('127.0.0.1', phone.port);
  }

  test('wrong code is rejected', () async {
    laptop.openPairing();
    final dev = await phone.probe('127.0.0.1', laptop.port);
    expect(() => phone.pair(dev, '000000'), throwsA(isA<SyncException>()));
  });

  test('pairing stores the peer on both sides and closes the code', () async {
    await pairDevices();
    expect(phone.library.peers().single.id, laptop.library.deviceId);
    expect(laptop.library.peers().single.id, phone.library.deviceId);
    expect(laptop.pairingCode.value, isNull);
  });

  test('library syncs both ways over HTTP', () async {
    await pairDevices();
    laptop.library.setLiked(_t('1'), true);
    final pid = laptop.library.createPlaylist('Road trip');
    laptop.library.addToPlaylist(pid, [_t('2'), _t('3')]);
    phone.library.setLiked(_t('9'), true);

    await phone.syncWith(laptop.library.deviceId);

    expect(phone.library.likedKeys(), {'youtube:1', 'youtube:9'});
    expect(phone.library.playlists().single.name, 'Road trip');
    expect(laptop.library.likedKeys(), {'youtube:1', 'youtube:9'});

    // Nothing new: the next round transfers nothing.
    expect(await phone.syncWith(laptop.library.deviceId), 0);
    // A later unlike on the phone reaches the laptop.
    phone.library.setLiked(_t('1'), false);
    await phone.syncWith(laptop.library.deviceId);
    expect(laptop.library.likedKeys(), {'youtube:9'});
  });

  test('requests without the shared token are refused', () async {
    await pairDevices();
    final peer = phone.library.peers().single;
    phone.library.savePeer(
      Peer(
        id: peer.id,
        name: peer.name,
        platform: peer.platform,
        token: 'forged',
        host: peer.host,
        port: peer.port,
      ),
    );
    expect(await phone.syncWith(peer.id), 0);
  });

  test('playback hands off and can be taken back', () async {
    await pairDevices();
    laptopPlayer.state = {
      'queue': [_t('5').toJson()],
      'index': 0,
      'positionMs': 42000,
      'playing': true,
    };
    await phone.takePlayback(laptop.library.deviceId);
    expect(phonePlayer.state['positionMs'], 42000);
    expect(laptopPlayer.paused, isTrue);

    await phone.sendPlayback(laptop.library.deviceId);
    expect(laptopPlayer.state['playing'], isTrue);
    expect(phonePlayer.paused, isTrue);
  });

  test('new device logs in with just the code and gets the library', () async {
    laptop.library.setLiked(_t('1'), true);
    final code = laptop.openPairing();
    await phone.probe('127.0.0.1', laptop.port); // seen via Bonjour
    await phone.joinWithCode(code);
    // Synced during pairing, before joinWithCode returned.
    expect(phone.library.likedKeys(), {'youtube:1'});
  });

  test('QR link pairs and a bad link is rejected', () async {
    laptop.openPairing();
    final link = (await laptop.pairingLink())!;
    // The test host's LAN address may not be reachable; point it at loopback.
    final local = Uri.parse(link).replace(
      queryParameters: {...Uri.parse(link).queryParameters, 'h': '127.0.0.1'},
    );
    await phone.joinWithLink(local.toString());
    expect(phone.library.peers().single.id, laptop.library.deviceId);
    expect(
      () => phone.joinWithLink('https://example.com'),
      throwsA(isA<SyncException>()),
    );
  });

  test('group membership spreads: phone learns about the tablet', () async {
    final tablet = SyncService(
      library: LibraryStore.memory(),
      player: FakePlayer(),
      enableDiscovery: false,
    );
    await tablet.start();
    addTearDown(tablet.dispose);

    // Tablet joins via the laptop, then the phone joins via the laptop.
    var code = laptop.openPairing();
    await tablet.pair(await tablet.probe('127.0.0.1', laptop.port), code);
    code = laptop.openPairing();
    await phone.pair(await phone.probe('127.0.0.1', laptop.port), code);

    expect(
      phone.library.peers().map((p) => p.id),
      contains(tablet.library.deviceId),
    );
    // Same secret everywhere: the phone can sync with the tablet directly.
    tablet.library.setLiked(_t('t'), true);
    final tabletPeer = phone.library.peer(tablet.library.deviceId)!;
    phone.library.savePeer(
      tabletPeer.copyWith(host: '127.0.0.1', port: tablet.port),
    );
    await phone.syncWith(tablet.library.deviceId);
    expect(phone.library.likedKeys(), contains('youtube:t'));
  });
}
