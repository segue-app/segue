import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/downloads/temp_cleanup.dart';

void main() {
  test('earlier runs\' seek copies go, this run\'s stay', () async {
    final sep = Platform.pathSeparator;
    final root = Directory('${Directory.systemTemp.path}${sep}segue_seek');
    final old = File('${root.path}${sep}old.mp3')..createSync(recursive: true);
    final otherRun = File('${root.path}${sep}1${sep}a.m4a')
      ..createSync(recursive: true);
    final mine = File('${root.path}$sep$pid${sep}b.m4a')
      ..createSync(recursive: true);

    await TempCleanup.run(updatesAfter: Duration.zero);

    expect(old.existsSync(), isFalse);
    expect(otherRun.existsSync(), isFalse);
    expect(mine.existsSync(), isTrue);
    mine.parent.deleteSync(recursive: true);
  });
}
