import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_store.dart';
import 'relay.dart';
import 'sync_service.dart';

/// One of this user's other devices, however we reach it.
@immutable
class MyDevice {
  const MyDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.online,
    this.remote,
  });

  final String id;
  final String name;
  final String platform;
  final bool online;

  /// Live state through the relay (what it plays), when connected.
  final RemoteDevice? remote;

  bool get playing => remote?.playing ?? false;
}

/// Devices, pairing and "play on…" over both transports: directly on the
/// same Wi-Fi ([SyncService]) and through the internet relay ([Relay]).
/// The relay is preferred; the local network keeps working without
/// internet.
class Connect {
  Connect({required this.sync, required this.relay, required this.library}) {
    library.changes.listen((_) => _peers.value++);
  }

  final _peers = ValueNotifier(0);

  final SyncService sync;
  final Relay relay;
  final LibraryStore library;

  /// Changes whenever a device appears, goes away or changes what it plays.
  Listenable get changes =>
      Listenable.merge([relay.devices, relay.connected, sync.nearby, _peers]);

  List<MyDevice> devices() {
    final out = <MyDevice>[];
    for (final p in library.peers()) {
      final r = relay.devices.value[p.id];
      out.add(
        MyDevice(
          id: p.id,
          name: r?.name ?? p.name,
          platform: r?.platform.isNotEmpty == true ? r!.platform : p.platform,
          online: (r?.online ?? false) || sync.isOnline(p.id),
          remote: r,
        ),
      );
    }
    out.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// The other device playing right now, if any.
  MyDevice? get playingElsewhere {
    for (final d in devices()) {
      if (d.playing) return d;
    }
    return null;
  }

  // --- pairing ---------------------------------------------------------------

  final inviteCode = ValueNotifier<String?>(null);

  /// Shows a code (and QR) that another device can use, on any network.
  Future<String> openInvite() async {
    String code;
    try {
      code = relay.connected.value ? await relay.openInvite() : _offlineCode();
    } catch (_) {
      code = _offlineCode();
    }
    sync.openPairing(code); // nearby devices can use the same code
    inviteCode.value = code;
    return code;
  }

  static String _offlineCode() {
    final now = DateTime.now().microsecondsSinceEpoch;
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(8, (i) => a[(now >> (i * 5)) % a.length]).join();
  }

  void closeInvite() {
    relay.closeInvite();
    sync.closePairing();
    inviteCode.value = null;
  }

  /// What the QR code encodes: the code, plus this device's address so a
  /// phone on the same Wi-Fi can connect directly.
  Future<String> inviteLink(String code) async {
    final host = await sync.localAddress();
    return Uri(
      scheme: 'segue',
      host: 'pair',
      queryParameters: {
        'c': code,
        'h': ?host,
        if (host != null) 'p': '${sync.port}',
        'n': sync.deviceName,
      },
    ).toString();
  }

  /// Joins with a typed code or a scanned link. Returns the other
  /// device's name.
  Future<String> join(String input) async {
    final uri = Uri.tryParse(input.trim());
    final isLink = uri != null && uri.scheme == 'segue';
    final code = isLink ? uri.queryParameters['c'] ?? '' : input;
    final errors = <String>[];
    if (relay.connected.value && Relay.normalizeCode(code) != null) {
      try {
        return await relay.join(code);
      } catch (e) {
        errors.add('$e');
      }
    }
    // Same Wi-Fi, no internet (or an older 6-digit code).
    try {
      final Peer peer = isLink && uri.queryParameters['h'] != null
          ? await sync.joinWithLink(input)
          : await sync.joinWithCode(code);
      await relay.restart(); // we joined their group: new relay channel
      return peer.name;
    } catch (e) {
      errors.add('$e');
    }
    throw SyncException(
      relay.connected.value
          ? 'Код не подошёл. Проверь его или покажи новый'
          : 'Нет интернета, и рядом в Wi-Fi нет устройства с этим кодом',
    );
  }

  // --- playback ----------------------------------------------------------------

  bool _viaRelay(String id) => relay.devices.value[id]?.online ?? false;

  /// Moves what plays here to [id] ("play on…").
  Future<void> handOffTo(String id) =>
      _viaRelay(id) ? relay.handOffTo(id) : sync.sendPlayback(id);

  /// Brings what plays on [id] here.
  Future<void> takeFrom(String id) =>
      _viaRelay(id) ? relay.takeFrom(id) : sync.takePlayback(id);

  /// Remote control of [id]: play, pause, next, prev, seek, volume, item.
  Future<void> command(String id, String op, [Map<String, dynamic>? args]) =>
      relay.command(id, op, args);

  /// Hides [id] here. It keeps the group secret, so to really cut it off,
  /// "Отключить это устройство" has to be pressed on it.
  void forget(String id) {
    relay.ignore(id);
    sync.unpair(id);
  }

  /// Leaves the group: this device gets a fresh secret and syncs with
  /// nobody until it is paired again. Its music stays.
  Future<void> leave() async {
    for (final p in library.peers()) {
      sync.unpair(p.id);
    }
    library.setMeta('group_token', '');
    library.setMeta('ignored_devices', '[]');
    await relay.restart();
  }
}

/// Created in main() and overridden there.
final connectProvider = Provider<Connect>(
  (ref) => throw UnimplementedError('connectProvider is overridden in main()'),
);
