// Live: listening together through the public relay brokers.
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/sync/jam.dart';

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
  test('host plays, friend follows and adds a song', () async {
    final hostPlayer = FakePlayer()
      ..state = {
        'queue': [_t('x1').toJson(), _t('x2').toJson()],
        'index': 0,
        'positionMs': 60000,
        'playing': true,
        'volume': 1.0,
        'durationMs': 200000,
      };
    final friendPlayer = FakePlayer();
    final host = JamService(
      player: hostPlayer,
      deviceId: 'host-device-0001',
      name: () => 'Akjol',
    );
    final friend = JamService(
      player: friendPlayer,
      deviceId: 'friend-device-01',
      name: () => 'Аян',
    );
    final code = await host.host();
    final events = <String>[];
    host.events.stream.listen(events.add);

    expect(await friend.join('segue://jam?c=$code'), 'Akjol');
    // The friend plays the same song, near the host's position.
    await _until(() => (friendPlayer.state['queue'] as List).isNotEmpty);
    expect((friendPlayer.state['queue'] as List).first['id'], 'x1');
    expect(friendPlayer.state['positionMs'] as int, greaterThan(59000));
    expect(friend.upcoming.value.map((t) => t.id), ['x2']);
    await _until(() => host.members.value.length == 2);

    // Host pauses: the friend pauses too.
    await hostPlayer.pause();
    await _until(() => friendPlayer.paused);

    // The friend adds a song: it lands next in the host's queue.
    await friend.suggest(_t('f1'));
    await _until(() => hostPlayer.calls.contains('add f1'));
    expect(hostPlayer.calls.where((c) => c == 'add f1'), hasLength(1));
    await _until(() => events.any((e) => e.contains('Song f1')));

    // Host ends it: the friend is told and leaves.
    await host.leave();
    await _until(() => !friend.active);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
