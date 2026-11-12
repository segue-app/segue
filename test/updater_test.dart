import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/integrations/updater.dart';
import 'package:segue/core/integrations/updates.dart';

void main() {
  test('picks the release file for this device', () {
    String? a(String os, [String v = '']) =>
        Updater.assetName(os: os, dartVersion: v);
    expect(a('android', '3.9 on "android_arm64"'), 'segue-android-arm64.apk');
    expect(a('android', '3.9 on "android_arm"'), 'segue-android-armv7.apk');
    expect(a('android', '3.9 on "android_x64"'), 'segue-android-x86_64.apk');
    expect(a('windows'), 'segue-windows-x64.zip');
    expect(a('linux'), 'segue-linux-x64.tar.gz');
    expect(a('macos'), 'segue-macos.zip');
    expect(a('ios'), isNull);
  });

  test('only offers an in-app update when the file is there', () {
    const without = AppUpdate('9.0.0', 'u', '');
    expect(Updater.canInstall(without), isFalse);
  });
}
