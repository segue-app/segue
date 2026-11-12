import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';

void main() {
  test('video titles are shown as song names', () {
    expect(
      prettyTitle(
        'Dua Lipa - Training Season (Live from the Royal Albert Hall) [Official Video]',
        'Dua Lipa',
      ),
      'Training Season (Live from the Royal Albert Hall)',
    );
    expect(prettyTitle('Мот - Капкан (премьера клипа, 2016)', 'МОТ'), 'Капкан');
    expect(prettyTitle('Zivert - Life | Official Audio | 2018', 'Zivert'), 'Life');
    // Someone else's upload keeps the artist in the title.
    expect(prettyTitle('Кино - Группа крови', 'Omnistar East'), 'Кино - Группа крови');
    expect(prettyTitle('(Official Video)', 'X'), '(Official Video)');
    expect(prettyTitle('Stay Alone', 'DVRST'), 'Stay Alone');
  });
}
