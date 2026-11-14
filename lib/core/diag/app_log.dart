import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The player's own notes (loads, mixes, beats) kept in a small file next
/// to the app's data, so a problem met while listening can be looked at
/// afterwards. Nothing leaves the device; the file stays under 512 KB.
class AppLog {
  static IOSink? _sink;

  /// Where it is (null until [start]).
  static String? path;

  /// Only the player's lines: what a mix went through.
  static bool _wanted(String m) =>
      m.startsWith('mix') ||
      m.startsWith('beat') ||
      m.startsWith('load ') ||
      m.startsWith('play ');

  static Future<void> start() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/player.log');
      if (f.existsSync() && f.lengthSync() > 512 * 1024) {
        f.renameSync('${dir.path}/player.old.log');
      }
      _sink = f.openWrite(mode: FileMode.append);
      path = f.path;
      final print = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        print(m, wrapWidth: wrapWidth);
        if (m != null && _wanted(m)) {
          _sink?.writeln('${DateTime.now().toIso8601String()} $m');
        }
      };
    } catch (_) {}
  }
}
