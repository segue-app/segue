import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/integrations/windows_media.dart';

void main() {
  test('covers Windows can open: web addresses and files only', () {
    expect(
      WindowsMedia.thumbnailFor(
        Uri.parse('https://i.ytimg.com/vi/x/hq720.jpg'),
      ),
      'https://i.ytimg.com/vi/x/hq720.jpg',
    );
    expect(
      WindowsMedia.thumbnailFor(
        Uri.file(r'C:\Users\me\Music\cover.jpg', windows: true),
      ),
      'file:///C:/Users/me/Music/cover.jpg',
    );
    // What Uri.parse makes of a bare Windows path: "c" as a scheme.
    expect(WindowsMedia.thumbnailFor(Uri.parse(r'C:\x\cover.jpg')), isNull);
    expect(WindowsMedia.thumbnailFor(null), isNull);
  });
}
