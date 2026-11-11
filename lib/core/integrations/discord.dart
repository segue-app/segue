import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../player/player_handler.dart';

/// Discord application id for "Listening to Segue". Created once at
/// discord.com/developers/applications and passed at build time with
/// `--dart-define=DISCORD_CLIENT_ID=...`; without it the status is off.
const discordClientId = String.fromEnvironment('DISCORD_CLIENT_ID');

/// "Слушает Segue" in the Discord profile: track, artist, cover and time.
///
/// Talks to the desktop Discord app over its local IPC socket (a named
/// pipe on Windows, a Unix socket on Linux). Not on macOS: the App
/// Sandbox doesn't allow connecting to Discord's socket.
class DiscordPresence {
  DiscordPresence({this.clientId = discordClientId});

  final String clientId;
  _Ipc? _ipc;
  Timer? _debounce;
  bool enabled = true;

  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// One frame of Discord's IPC protocol: opcode and length (little
  /// endian int32 each), then JSON. Exposed for tests.
  static Uint8List frame(int op, Map<String, dynamic> body) {
    final json = utf8.encode(jsonEncode(body));
    final out = ByteData(8 + json.length)
      ..setInt32(0, op, Endian.little)
      ..setInt32(4, json.length, Endian.little);
    final bytes = out.buffer.asUint8List()..setRange(8, 8 + json.length, json);
    return bytes;
  }

  /// The activity Discord shows for [item]. Exposed for tests.
  static Map<String, dynamic> activity({
    required String title,
    required String artist,
    String? cover,
    Duration? position,
    Duration? duration,
    required bool playing,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - (position?.inMilliseconds ?? 0);
    String cut(String s) => s.length > 120 ? '${s.substring(0, 119)}…' : s;
    return {
      'type': 2, // "Listening to"
      'details': cut(title.isEmpty ? 'Segue' : title),
      'state': cut(playing ? (artist.isEmpty ? ' ' : artist) : 'На паузе'),
      if (playing)
        'timestamps': {
          'start': start,
          if (duration != null) 'end': start + duration.inMilliseconds,
        },
      'assets': {
        if (cover != null && cover.startsWith('https://')) 'large_image': cover,
        'large_text': cut(title),
      },
    };
  }

  void attach(SegueAudioHandler player) {
    if (!supported || clientId.isEmpty) return;
    void schedule() {
      _debounce?.cancel();
      // Discord accepts ~5 updates per 20 s: send only once things settle.
      _debounce = Timer(const Duration(milliseconds: 1500), () {
        final item = player.mediaItem.value;
        final st = player.playbackState.value;
        if (!enabled || item == null) {
          _send(null);
          return;
        }
        _send(
          activity(
            title: item.title,
            artist: item.artist ?? '',
            cover: item.artUri?.toString(),
            position: st.updatePosition,
            duration: item.duration,
            playing: st.playing,
          ),
        );
      });
    }

    player.mediaItem.listen((_) => schedule());
    player.playbackState
        .map((s) => s.playing)
        .distinct()
        .listen((_) => schedule());
  }

  Future<void> _send(Map<String, dynamic>? activity) async {
    try {
      final ipc = _ipc ??= await _Ipc.connect(clientId);
      if (ipc == null) return;
      ipc.write(
        frame(1, {
          'cmd': 'SET_ACTIVITY',
          'args': {'pid': pid, 'activity': activity},
          'nonce': '${DateTime.now().microsecondsSinceEpoch}',
        }),
      );
    } catch (e) {
      // Discord was closed: reconnect on the next update.
      debugPrint('discord: $e');
      _ipc?.close();
      _ipc = null;
    }
  }
}

/// The socket or pipe to the Discord app.
class _Ipc {
  _Ipc._(this._write, this._close);

  final void Function(Uint8List) _write;
  final void Function() _close;

  void write(Uint8List data) => _write(data);
  void close() => _close();

  static Future<_Ipc?> connect(String clientId) async {
    final hello = DiscordPresence.frame(0, {'v': 1, 'client_id': clientId});
    for (var i = 0; i < 10; i++) {
      try {
        if (Platform.isWindows) {
          final pipe = await File(
            r'\\?\pipe\discord-ipc-'
            '$i',
          ).open(mode: FileMode.append);
          final ipc = _Ipc._(
            (d) => pipe.writeFromSync(d),
            () => pipe.closeSync(),
          );
          ipc.write(hello);
          return ipc;
        }
        for (final dir in _linuxDirs()) {
          final path = '$dir/discord-ipc-$i';
          if (!File(path).existsSync() &&
              FileSystemEntity.typeSync(path) ==
                  FileSystemEntityType.notFound) {
            continue;
          }
          final socket = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
          ).timeout(const Duration(seconds: 2));
          // Replies aren't needed; reading keeps the socket healthy.
          socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
          final ipc = _Ipc._(socket.add, socket.destroy);
          ipc.write(hello);
          return ipc;
        }
      } catch (_) {}
    }
    return null;
  }

  static List<String> _linuxDirs() {
    final env = Platform.environment;
    final base =
        env['XDG_RUNTIME_DIR'] ?? env['TMPDIR'] ?? env['TMP'] ?? '/tmp';
    return [
      base,
      '$base/app/com.discordapp.Discord', // Flatpak
      '$base/snap.discord', // Snap
      '/tmp',
    ];
  }
}
