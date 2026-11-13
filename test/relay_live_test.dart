// Live: two devices on different "networks" talking through the public
// relay brokers. Run: flutter test --tags live test/relay_live_test.dart
@Tags(['live'])
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:segue/core/library/library_store.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sync/relay.dart';

import 'support/fake_player.dart';

Track _t(String id) =>
    Track(id: id, source: SourceKind.youtube, title: 'Song $id', artist: 'A');

Future<void> _until(bool Function() ok, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw StateError('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  test('pair by code, sync the library, control playback', () async {
    final libA = LibraryStore.memory(), libB = LibraryStore.memory();
    final playerA = FakePlayer(), playerB = FakePlayer();
    // A has a library already; B is a fresh phone with one like of its own.
    libA.setLiked(_t('a1'), true);
    final pl = libA.createPlaylist('Вечер');
    libA.addToPlaylist(pl, [_t('a2'), _t('a3')]);
    libB.setLiked(_t('b1'), true);

    final a = Relay(library: libA, player: playerA, deviceName: () => 'Mac');
    final b = Relay(library: libB, player: playerB, deviceName: () => 'Phone');
    await a.start();
    await b.start();
    expect(a.connected.value && b.connected.value, isTrue);

    final code = await a.openInvite();
    expect(Relay.normalizeCode(code.toLowerCase()), code);
    final host = await b.join(code);
    expect(host, 'Mac');

    // Everything arrives both ways: likes, playlists with their tracks.
    await _until(() => libB.isLiked(_t('a1')) && libA.isLiked(_t('b1')));
    await _until(() => libB.playlists().any((p) => p.name == 'Вечер'));
    final onB = libB.playlists().firstWhere((p) => p.name == 'Вечер');
    expect(libB.playlistTracks(onB.id).map((t) => t.id), ['a2', 'a3']);
    expect(a.devices.value[libB.deviceId]?.online, isTrue);

    // A plays; B sees it and controls it.
    playerA.state = {
      'queue': [_t('a2').toJson(), _t('a3').toJson()],
      'index': 0,
      'positionMs': 30000,
      'playing': true,
      'volume': 1.0,
      'durationMs': 200000,
    };
    await playerA.play();
    await _until(() => b.devices.value[libA.deviceId]?.playing == true);
    expect(b.devices.value[libA.deviceId]!.track?['id'], 'a2');
    await b.command(libA.deviceId, 'seek', {'ms': 90000});
    await b.command(libA.deviceId, 'next');
    await _until(() => playerA.calls.contains('next'));
    expect(playerA.calls.where((c) => c == 'next'), hasLength(1)); // deduped
    expect(playerA.calls, contains('seek 90'));

    // Bring the music to B: it continues where A was; A pauses.
    await b.takeFrom(libA.deviceId);
    await _until(() => playerA.paused);
    expect(playerB.state['playing'], isTrue);
    expect(playerB.state['positionMs'] as int, greaterThanOrEqualTo(90000));

    a.closeInvite();
    await a.stop();
    await b.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('positions stay right when the clocks disagree', () async {
    final libA = LibraryStore.memory(), libB = LibraryStore.memory();
    final playerA = FakePlayer(), playerB = FakePlayer();
    final a = Relay(library: libA, player: playerA, deviceName: () => 'Mac')
      // The Mac's clock is a minute behind.
      ..clockOffset = const Duration(seconds: -60);
    var b = Relay(library: libB, player: playerB, deviceName: () => 'Phone');
    await a.start();
    await b.start();
    await b.join(await a.openInvite());
    playerA.state = {
      'queue': [_t('a2').toJson()],
      'index': 0,
      'positionMs': 30000,
      'playing': true,
      'durationMs': 200000,
    };
    await playerA.play();
    await _until(() => b.devices.value[libA.deviceId]?.playing == true);
    Duration seen() => b.devices.value[libA.deviceId]!.position;
    // ignore: avoid_print
    print('CLOCK live: ${seen().inSeconds}s');
    expect(seen().inSeconds, inInclusiveRange(29, 37));

    // The phone reconnects and first gets the stored message.
    await b.stop();
    b = Relay(library: libB, player: playerB, deviceName: () => 'Phone');
    await b.start();
    await _until(() => b.devices.value[libA.deviceId]?.playing == true);
    // A fresh heartbeat corrects it within seconds.
    await Future<void>.delayed(const Duration(seconds: 7));
    // ignore: avoid_print
    print('CLOCK after reconnect: ${seen().inSeconds}s');
    expect(seen().inSeconds, inInclusiveRange(29, 37));
    a.closeInvite();
    await a.stop();
    await b.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('one dropped broker connection does not take a device offline', () async {
    final libA = LibraryStore.memory(), libB = LibraryStore.memory();
    final a = Relay(library: libA, player: FakePlayer(), deviceName: () => 'Mac');
    final b = Relay(library: libB, player: FakePlayer(), deviceName: () => 'Phone');
    await a.start();
    await b.start();
    await b.join(await a.openInvite());
    await _until(() => b.devices.value[libA.deviceId]?.online == true);

    // What a broker sends when one of A's two connections dies: its will,
    // a plain "off", on that broker only.
    final token = libA.getMeta('group_token')!;
    final base =
        'segue/v1/${(await Relay.hash('segue-topic:$token')).substring(0, 24)}';
    final c = MqttServerClient.withPort(
      'broker.emqx.io',
      'sg-test-${Random().nextInt(1 << 30)}',
      8883,
    )..secure = true;
    await c.connect();
    c.publishMessage(
      '$base/p/${libA.deviceId}',
      MqttQos.atLeastOnce,
      Uint8Buffer()..addAll('off'.codeUnits),
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    final online = b.devices.value[libA.deviceId]?.online;
    // ignore: avoid_print
    print('PRESENCE after one broker said off: online=$online');
    expect(online, isTrue);
    c.disconnect();
    a.closeInvite();
    await a.stop();
    await b.stop();
    // A really leaving is still seen.
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('settings follow you to another device, its own stay', () async {
    final libA = LibraryStore.memory(), libB = LibraryStore.memory();
    final a = Relay(library: libA, player: FakePlayer(), deviceName: () => 'Mac');
    final b = Relay(library: libB, player: FakePlayer(), deviceName: () => 'Phone');
    // The phone has its own interface scale; a fresh install otherwise.
    libB.setMeta('appearance', '{"textScale":1.3}');
    await a.start();
    await b.start();
    await b.join(await a.openInvite());
    // On the Mac: a new accent font and an equalizer preset.
    libA
      ..setMeta('appearance', '{"font":"Inter","textScale":0.9}')
      ..setMeta('audio_fx', '{"preset":"Бас","eqOn":true}')
      ..touchPrefs();
    await _until(() => (libB.getMeta('audio_fx') ?? '').contains('Бас'));
    final app = libB.getMeta('appearance')!;
    // ignore: avoid_print
    print('PREFS on the phone: $app');
    expect(app, contains('"font":"Inter"'));
    expect(app, contains('"textScale":1.3')); // its own, kept
    a.closeInvite();
    await a.stop();
    await b.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
