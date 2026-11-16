// ignore_for_file: avoid_print
// Asks the public YouTube mirrors from this machine (network required).
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/sources/yt_mirrors.dart';

void main() {
  test('mirror search', () async {
    final found = await YtMirrors().search('rick astley never gonna');
    print(
      '${found.length} found, first ${found.first.id} ${found.first.title}',
    );
    expect(found, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('mirror audio', () async {
    try {
      final a = await YtMirrors().audio('dQw4w9WgXcQ', (_) async => true);
      print('audio ${a.mimeType} ${a.url.host}');
    } catch (e) {
      print('no mirror audio: $e');
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
