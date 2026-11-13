import 'dart:convert';
import 'dart:typed_data';

import '../catalog/taste.dart';
import '../integrations/updates.dart';
import 'library_store.dart';

/// Everything that's yours in one file: liked songs, playlists, history,
/// the synced settings and what My wave has learnt. Restoring merges it
/// into the library (the newer version of each row wins), so it's safe
/// on a device that already has music, and the paired devices get it too.
class Backup {
  Backup._();

  static const format = 'segue-backup';

  static String fileName(DateTime now) =>
      'segue-backup-${now.year}-${_two(now.month)}-${_two(now.day)}.json';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static Map<String, dynamic> build(LibraryStore library, {Taste? taste}) => {
    'format': format,
    'version': 1,
    'app': appVersion,
    'at': DateTime.now().millisecondsSinceEpoch,
    'library': library.exportChanges(0)..remove('seq'),
    'prefs': library.exportPrefs(),
    'taste': ?taste?.export(),
  };

  static Uint8List encode(LibraryStore library, {Taste? taste}) =>
      Uint8List.fromList(utf8.encode(jsonEncode(build(library, taste: taste))));

  /// Reads a backup file; throws [FormatException] if it isn't one.
  static Map<String, dynamic> decode(List<int> bytes) {
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('not a Segue backup');
    }
    if (j is! Map || j['format'] != format || j['library'] is! Map) {
      throw const FormatException('not a Segue backup');
    }
    return j.cast<String, dynamic>();
  }

  /// Merges [backup] into [library]. The backup's settings replace the
  /// current ones (this device's own screen settings stay).
  static BackupSummary restore(
    LibraryStore library,
    Map<String, dynamic> backup, {
    Taste? taste,
  }) {
    final lib = (backup['library'] as Map).cast<String, dynamic>();
    final liked = (lib['likes'] as List? ?? const [])
        .whereType<Map>()
        .where((r) => r['deleted'] == 0)
        .length;
    final playlists = (lib['playlists'] as List? ?? const [])
        .whereType<Map>()
        .where((r) => r['deleted'] == 0)
        .length;
    final rows = library.applyChanges(lib);
    final prefs = backup['prefs'];
    if (prefs is Map && prefs.length > 1) {
      // Chosen now, so it wins over what's set here and on paired devices.
      final p = prefs.cast<String, dynamic>()
        ..['at'] = DateTime.now().millisecondsSinceEpoch;
      if (library.importPrefs(p)) library.touchPrefs();
    }
    final t = backup['taste'];
    if (taste != null && t is Map) taste.merge(t.cast<String, dynamic>());
    return BackupSummary(liked: liked, playlists: playlists, changed: rows);
  }
}

class BackupSummary {
  const BackupSummary({
    required this.liked,
    required this.playlists,
    required this.changed,
  });

  /// Liked songs and playlists in the file.
  final int liked;
  final int playlists;

  /// Rows that were new or newer than what was here.
  final int changed;
}
