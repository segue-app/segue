import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Leftovers of earlier runs:
/// * segue_seek — whole-file copies of HLS songs made for seeking
///   (DownloadManager.seekableCopy), meant for one session but never
///   removed: on a Mac they had grown past a GB. Now one folder per run
///   (by pid); the earlier runs' ones go at start.
/// * updates — the downloaded APK or archive of an update that is
///   installed by now (Android, Windows, Linux). Removed a little later:
///   the Windows/Linux update script may still be finishing in there while
///   the new version starts.
class TempCleanup {
  static String get _seek =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}segue_seek';

  static Future<void> run({
    Duration updatesAfter = const Duration(seconds: 20),
  }) async {
    // Everything but this run's own folder (named by its pid).
    final seek = Directory(_seek);
    try {
      if (await seek.exists()) {
        await for (final e in seek.list()) {
          if (e.path.endsWith('${Platform.pathSeparator}$pid')) continue;
          try {
            await e.delete(recursive: true);
          } catch (err) {
            debugPrint('cleanup ${e.path}: $err');
          }
        }
      }
    } catch (e) {
      debugPrint('cleanup $_seek: $e');
    }
    await Future<void>.delayed(updatesAfter);
    try {
      final t = await getTemporaryDirectory();
      await _remove(Directory('${t.path}${Platform.pathSeparator}updates'));
    } catch (_) {
      // No path_provider (tests): nothing was downloaded.
    }
  }

  static Future<void> _remove(Directory d) async {
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      debugPrint('cleanup ${d.path}: $e');
    }
  }
}
