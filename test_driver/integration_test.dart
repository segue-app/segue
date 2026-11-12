import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Writes screenshots captured inside the app (base64 in reportData) to
/// the directory in SEGUE_SHOTS_DIR (default: build/screenshots).
Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      final dir = Directory(Platform.environment['SEGUE_SHOTS_DIR'] ?? 'build/screenshots')
        ..createSync(recursive: true);
      for (final e in (data ?? {}).entries) {
        File('${dir.path}/${e.key}.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(base64Decode(e.value as String));
      }
    });
