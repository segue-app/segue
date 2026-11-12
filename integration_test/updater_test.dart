// Downloads the real latest release and unpacks it the way the app does
// on macOS (no Finder window). Network needed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:segue/core/integrations/updater.dart';
import 'package:segue/core/integrations/updates.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS: update downloads and unpacks a runnable app', (
    tester,
  ) async {
    final latest = await checkForUpdateFrom('0.0.1');
    expect(latest, isNotNull);
    final u = Updater()..revealInFinder = false;
    final seen = <double>[];
    u.progress.addListener(() {
      final p = u.progress.value;
      if (p != null) seen.add(p);
    });
    await u.install(latest!);
    expect(u.stage.value, UpdateStage.done, reason: u.message.value);
    final app = Directory(u.unpackedPath!);
    final exe = File('${app.path}/Contents/MacOS/Segue');
    final codesign = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      app.path,
    ]);
    // ignore: avoid_print
    print(
      'UPDATER: ${latest.version} → ${app.path}, progress steps '
      '${seen.length}, last ${seen.last}, exe ${exe.existsSync()}, '
      'codesign ${codesign.exitCode} ${codesign.stderr}',
    );
    expect(exe.existsSync(), isTrue);
    expect(seen.last, 1.0);
    expect(codesign.exitCode, 0);
    app.parent.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
