import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/recognize/shazam.dart';
import 'package:segue/core/recognize/shazam_signature.dart';
import 'package:segue/core/recognize/song_listener.dart';

/// [seconds] of a tone at [hz], 16 kHz mono.
Int16List tone(double hz, double seconds) {
  final n = (seconds * 16000).round();
  return Int16List.fromList([
    for (var i = 0; i < n; i++)
      // Swells twice a second, smoothly: peaks stand out in time too.
      ((sin(2 * pi * hz * i / 16000) * (7000 + 5000 * sin(2 * pi * i / 8000))))
          .round(),
  ]);
}

void main() {
  test('a 440 Hz tone: its peaks are at 440 Hz, in the lowest band', () {
    final sig = ShazamSignature.of(tone(440, 6));
    final all = [for (final b in sig.bands) ...b];
    final at440 = sig.bands[0].where(
      (p) => (p.bin * (16000 / 2 / 1024 / 64) - 440).abs() < 15,
    );
    expect(at440, isNotEmpty);
    expect(at440.length, greaterThan(all.length * 0.8));
    expect(sig.length, const Duration(seconds: 6));
  });

  test('silence and flat sound don\'t break it', () {
    expect(ShazamSignature.of(Int16List(16000 * 3)).peakCount, 0);
    expect(
      () =>
          ShazamSignature.of(Int16List.fromList(List.filled(16000 * 3, 1000))),
      returnsNormally,
    );
  });

  test('the message has Shazam\'s header and a correct checksum', () {
    final sig = ShazamSignature.of(tone(1000, 4));
    final msg = sig.encode();
    final d = ByteData.sublistView(msg);
    expect(d.getUint32(0, Endian.little), 0xcafe2580);
    expect(d.getUint32(12, Endian.little), 0x94119c00);
    expect(d.getUint32(8, Endian.little), msg.length - 48);
    expect(d.getUint32(28, Endian.little), 3 << 27); // 16 kHz
    expect(d.getUint32(40, Endian.little), 4 * 16000 + 3840);
    expect(d.getUint32(4, Endian.little), getCrc32(msg.sublist(8)));
    expect(sig.uri, startsWith('data:audio/vnd.shazam.sig;base64,'));
    expect(base64.decode(sig.uri.split(',').last), msg);
  });

  test('peaks are written in time order, each band padded to 4 bytes', () {
    final sig = ShazamSignature.of(tone(700, 5));
    for (final band in sig.bands) {
      for (var i = 1; i < band.length; i++) {
        expect(band[i].pass, greaterThanOrEqualTo(band[i - 1].pass));
      }
    }
    expect((sig.encode().length - 56) % 4, 0);
  });

  test('Shazam\'s answer: a match, and no match', () {
    final song = Shazam.parse({
      'matches': [
        {'id': '1'},
      ],
      'track': {
        'title': 'Bari Biled',
        'subtitle': 'Ninety One',
        'url': 'https://www.shazam.com/track/1',
        'images': {
          'coverart': 'https://a/c.jpg',
          'coverarthq': 'https://a/hq.jpg',
        },
        'sections': [
          {
            'type': 'SONG',
            'metadata': [
              {'title': 'Album', 'text': 'Men Emes - EP'},
              {'title': 'Released', 'text': '2016'},
            ],
          },
        ],
      },
    })!;
    expect(song.title, 'Bari Biled');
    expect(song.artist, 'Ninety One');
    expect(song.coverUrl, 'https://a/hq.jpg');
    expect(song.album, 'Men Emes - EP');
    expect(song.year, '2016');
    expect(song.track.title, 'Bari Biled');
    expect(RecognizedSong.fromJson(song.toJson())!.album, 'Men Emes - EP');

    expect(Shazam.parse({'matches': [], 'tagid': 'x'}), isNull);
    expect(Shazam.parse('nonsense'), isNull);
  });

  test('loudness: silence 0, full scale 1, quiet in between', () {
    Uint8List pcm(int amp) {
      final b = ByteData(3200);
      for (var i = 0; i < 1600; i++) {
        b.setInt16(i * 2, i.isEven ? amp : -amp, Endian.little);
      }
      return b.buffer.asUint8List();
    }

    expect(SongListener.loudness(pcm(0)), 0);
    expect(SongListener.loudness(pcm(32767)), closeTo(1, 0.01));
    final quiet = SongListener.loudness(pcm(330)); // about -40 dBFS
    expect(quiet, closeTo(1 / 3, 0.05));
    expect(SongListener.loudness(Uint8List(0)), 0);
  });
}
