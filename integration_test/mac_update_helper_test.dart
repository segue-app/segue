// Starts the real macOS update helper on THIS test build: it downloads the
// latest release, quits this app, replaces build/…/Debug/Segue.app with it
// and opens it. The test can't see the end (it's quit); check afterwards.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:segue/core/integrations/updates.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('helper takes over', (tester) async {
    final latest = await checkForUpdateFrom('0.0.1');
    const ch = MethodChannel('fm.segue/update');
    final r = await ch.invokeMethod<String>('install', {
      'url': latest!.assets['segue-macos.zip']!,
      'version': latest.version,
      'title': 'Segue',
      'downloading': 'Downloading',
      'installing': 'Installing…',
      'failed': 'Update failed',
    });
    // ignore: avoid_print
    print('HELPER started: $r');
    expect(r, 'ok');
    await Future<void>.delayed(const Duration(minutes: 3));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
