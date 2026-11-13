import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/share/track_link.dart';

void main() {
  test('a shared song comes back as the same song', () {
    const imported = Track(
      id: 'МОТ — Капкан',
      source: SourceKind.match,
      title: 'Капкан',
      artist: 'МОТ',
      artworkUrl: 'https://cdn-images.dzcdn.net/x/1000x1000.jpg',
      duration: Duration(seconds: 228),
    );
    final link = TrackLink.webLink(imported, youtubeId: 'U9vbmWx4zt0');
    expect(link, startsWith(TrackLink.web));
    expect(link.length, lessThan(90)); // was 313 with everything inside
    final back = TrackLink.decode(Uri.parse(link))!;
    expect(back.track.key, imported.key);
    expect(back.track.title, 'Капкан');
    expect(back.youtubeId, 'U9vbmWx4zt0');
    // The app's own link carries the same data.
    final app = Uri.parse('segue://track?d=${TrackLink.encode(imported)}');
    expect(TrackLink.decode(app)!.track.artist, 'МОТ');
  });

  test('a YouTube song keeps its video', () {
    const yt = Track(
      id: 'kJQP7kiw5Fk',
      source: SourceKind.youtube,
      title: 'Luis Fonsi - Despacito ft. Daddy Yankee',
      artist: 'Luis Fonsi',
    );
    final back = TrackLink.decode(Uri.parse(TrackLink.webLink(yt)))!;
    expect(back.track.source, SourceKind.youtube);
    expect(back.track.id, 'kJQP7kiw5Fk');
    expect(back.track.title, 'Despacito ft. Daddy Yankee');
  });

  test('broken links are ignored', () {
    expect(TrackLink.decode(Uri.parse('segue://track?d=@@@')), isNull);
    expect(TrackLink.decode(Uri.parse('https://x.y/t/')), isNull);
  });

  test('old long links still open', () {
    const old =
        'https://segue-app.github.io/segue/t/#eyJzIjoibSIsImlkIjoi0JzQntCiIOKAlCDQmtCw0L_QutCw0L0iLCJ0Ijoi0JrQsNC_0LrQsNC9IiwiYSI6ItCc0J7QoiIsInkiOiJVOXZibVd4NHp0MCIsImQiOjIyOH0';
    final back = TrackLink.decode(Uri.parse(old))!;
    expect(back.track.title, 'Капкан');
    expect(back.youtubeId, 'U9vbmWx4zt0');
  });
}
