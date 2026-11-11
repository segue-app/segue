// Live: two devices on different "networks" talking through the public
// relay brokers. Run: flutter test --tags live test/relay_live_test.dart
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
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
}
