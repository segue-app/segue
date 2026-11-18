import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/models/track.dart';
import 'package:segue/core/share/invite_link.dart';
import 'package:segue/core/sources/soundcloud_source.dart';
import 'package:segue/core/sources/stand_in.dart';
import 'package:segue/core/sources/youtube_source.dart';

class _FakeSoundCloud extends SoundCloudSource {
  _FakeSoundCloud(this.results);

  final List<Track> results;
  final queries = <String>[];

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    queries.add(query);
    return results;
  }
}

Track _sc(String id, String title, String artist, int secs) => Track(
  id: id,
  source: SourceKind.soundcloud,
  title: title,
  artist: artist,
  duration: Duration(seconds: secs),
);

void main() {
  const wanted = Track(
    id: 'x',
    source: SourceKind.match,
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    duration: Duration(seconds: 200),
  );

  test('stand-in picks the same song, not a remix', () async {
    final sc = _FakeSoundCloud([
      _sc('1', 'Blinding Lights (Slowed + Reverb)', 'some fan', 260),
      _sc('2', 'Blinding Lights', 'The Weeknd', 201),
      _sc('3', 'Save Your Tears', 'The Weeknd', 215),
    ]);
    final found = await StandIn([sc]).find(wanted);
    expect(found?.id, '2');
    expect(sc.queries.single, 'The Weeknd Blinding Lights');
  });

  test('stand-in refuses a song that is not there', () async {
    final sc = _FakeSoundCloud([
      _sc('1', 'Blinding Lights cover', 'someone', 190),
      _sc('2', 'Blinding Lights', 'The Weeknd', 30), // a preview
    ]);
    expect(await StandIn([sc]).find(wanted), isNull);
  });

  test('a YouTube title becomes song and artist', () {
    final t = YouTubeSource.songOf(
      const Track(
        id: 'v',
        source: SourceKind.youtube,
        title: 'The Weeknd - Blinding Lights (Official Video)',
        artist: 'TheWeekndVEVO',
      ),
    );
    expect(t.artist, 'The Weeknd');
    expect(t.title, 'Blinding Lights (Official Video)');
  });

  test('invite links are https and carry the code', () {
    final p = InviteLink.playlist('ABCD2345');
    expect(p, startsWith('https://'));
    expect(InviteLink.code(p), 'ABCD2345');
    expect(InviteLink.code(InviteLink.jam('WXYZ6789')), 'WXYZ6789');
    expect(InviteLink.code('segue://jam?c=WXYZ6789'), 'WXYZ6789');
    expect(InviteLink.code('ABCD-2345'), isNull); // a bare code
  });
}
