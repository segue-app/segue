// The audio fingerprint Shazam's servers read, made on the device.
//
// Ported from SongRec by marin-m (https://github.com/marin-m/SongRec,
// GPL-3.0, like Segue): src/core/fingerprinting/algorithm.rs and
// signature_format.rs. Only the fingerprint (peaks of the spectrum, a few
// kilobytes) is sent, never the recording itself.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// A spectral peak: when (in 128-sample steps), how loud, which frequency
/// (FFT bin × 64).
class FrequencyPeak {
  const FrequencyPeak(this.pass, this.magnitude, this.bin);

  final int pass;
  final int magnitude;
  final int bin;
}

/// A Shazam signature of 16 kHz mono audio.
class ShazamSignature {
  ShazamSignature._(this.numberSamples, this.bands);

  static const sampleRate = 16000;

  final int numberSamples;

  /// Peaks of the four frequency bands: 250–520 Hz, 520–1450 Hz,
  /// 1450–3500 Hz and 3500–5500 Hz.
  final List<List<FrequencyPeak>> bands;

  int get peakCount => bands.fold(0, (n, b) => n + b.length);

  Duration get length =>
      Duration(microseconds: numberSamples * 1000000 ~/ sampleRate);

  /// Fingerprints [samples]: signed 16-bit, 16 kHz, mono. Shazam wants
  /// about 12 seconds; more isn't better.
  static ShazamSignature of(Int16List samples) {
    final g = _Generator(samples.length);
    for (var i = 0; i + 128 <= samples.length; i += 128) {
      g.feed(samples, i);
    }
    return ShazamSignature._(samples.length, g.bands);
  }

  /// The binary message (header, then the peaks band by band).
  Uint8List encode() {
    final body = BytesBuilder();
    void u32(BytesBuilder b, int v) => b.add(
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
    );
    void u16(BytesBuilder b, int v) => b.add(
      (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
    );

    for (var band = 0; band < bands.length; band++) {
      final peaks = bands[band];
      if (peaks.isEmpty) continue;
      final p = BytesBuilder();
      var pass = 0;
      for (final peak in peaks) {
        if (peak.pass - pass >= 255) {
          p.addByte(0xff);
          u32(p, peak.pass);
          pass = peak.pass;
        }
        p.addByte(peak.pass - pass);
        u16(p, peak.magnitude);
        u16(p, peak.bin);
        pass = peak.pass;
      }
      final bytes = p.takeBytes();
      u32(body, 0x60030040 + band);
      u32(body, bytes.length);
      body.add(bytes);
      body.add(Uint8List((4 - bytes.length % 4) % 4));
    }
    final contents = body.takeBytes();

    final out = BytesBuilder();
    u32(out, 0xcafe2580); // magic
    u32(out, 0); // CRC-32, filled in below
    u32(out, contents.length + 8); // size after the header
    u32(out, 0x94119c00); // magic
    for (var i = 0; i < 3; i++) {
      u32(out, 0);
    }
    u32(out, 3 << 27); // sample rate id: 3 is 16 kHz
    u32(out, 0);
    u32(out, 0);
    u32(out, numberSamples + (sampleRate * 0.24).toInt());
    u32(out, (15 << 19) + 0x40000);
    u32(out, 0x40000000);
    u32(out, contents.length + 8);
    out.add(contents);
    final msg = out.takeBytes();
    ByteData.sublistView(msg).setUint32(4, _crc32(msg, 8), Endian.little);
    return msg;
  }

  String get uri =>
      'data:audio/vnd.shazam.sig;base64,${base64.encode(encode())}';

  static final _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int _crc32(Uint8List data, int from) {
    var c = 0xffffffff;
    for (var i = from; i < data.length; i++) {
      c = _crcTable[(c ^ data[i]) & 0xff] ^ (c >> 8);
    }
    return (c ^ 0xffffffff) & 0xffffffff;
  }
}

class _Generator {
  _Generator(int numberSamples);

  final bands = List.generate(4, (_) => <FrequencyPeak>[]);

  final _ring = Int16List(2048);
  var _ringIndex = 0;

  final _ffts = List.generate(256, (_) => Float64List(1025));
  var _fftIndex = 0;
  final _spread = List.generate(256, (_) => Float64List(1025));
  var _spreadIndex = 0;
  var _spreadDone = 0;

  final _re = Float64List(2048);
  final _im = Float64List(2048);

  /// A Hann window without its zero ends (numpy's hanning(2050)[1:-1]).
  static final _window = Float64List.fromList([
    for (var i = 0; i < 2048; i++)
      0.5 - 0.5 * math.cos(2 * math.pi * (i + 1) / 2049),
  ]);

  void feed(Int16List samples, int at) {
    _ring.setRange(_ringIndex, _ringIndex + 128, samples, at);
    _ringIndex = (_ringIndex + 128) & 2047;
    _fft();
    _spreadPeaks();
    _spreadDone++;
    if (_spreadDone >= 46) _recognize();
  }

  void _fft() {
    for (var i = 0; i < 2048; i++) {
      _re[i] = _ring[(i + _ringIndex) & 2047] * _window[i];
      _im[i] = 0;
    }
    _Fft.transform(_re, _im);
    final out = _ffts[_fftIndex];
    for (var i = 0; i < 1025; i++) {
      out[i] = math.max(
        (_re[i] * _re[i] + _im[i] * _im[i]) / (1 << 17),
        0.0000000001,
      );
    }
    _fftIndex = (_fftIndex + 1) & 255;
  }

  void _spreadPeaks() {
    final last = _ffts[(_fftIndex - 1) & 255];
    final s = _spread[_spreadIndex]..setAll(0, last);
    // Across frequency…
    for (var p = 0; p <= 1022; p++) {
      s[p] = math.max(s[p], math.max(s[p + 1], s[p + 2]));
    }
    // …and back in time.
    for (final back in const [1, 3, 6]) {
      final former = _spread[(_spreadIndex - back) & 255];
      for (var p = 0; p <= 1024; p++) {
        if (s[p] > former[p]) former[p] = s[p];
      }
    }
    _spreadIndex = (_spreadIndex + 1) & 255;
  }

  /// Rust's `as i32`: NaN is 0 and the infinities saturate. A flat peak
  /// (equal neighbours) divides 0 by 0 here; truncating that would throw.
  static int _asI32(double v) {
    if (v.isNaN) return 0;
    if (v >= 2147483647) return 2147483647;
    if (v <= -2147483648) return -2147483648;
    return v.truncate();
  }

  static double _mag(double v) => math.max(math.log(v), 1 / 64) * 1477.3 + 6144;

  void _recognize() {
    final f46 = _ffts[(_fftIndex - 46) & 255];
    final s49 = _spread[(_spreadIndex - 49) & 255];
    for (var bin = 10; bin <= 1014; bin++) {
      final v = f46[bin];
      if (v < 1 / 64 || v < s49[bin - 1]) continue;
      var around = 0.0;
      for (final o in const [-10, -7, -4, -3, 1, 2, 5, 8]) {
        around = math.max(around, s49[bin + o]);
      }
      if (v <= around) continue;
      var near = around;
      for (final o in const [
        -53, -45, 165, 172, 179, 186, 193, 200, //
        214, 221, 228, 235, 242, 249,
      ]) {
        near = math.max(near, _spread[(_spreadIndex + o) & 255][bin - 1]);
      }
      if (v <= near) continue;

      final mag = _mag(v);
      final before = _mag(f46[bin - 1]);
      final after = _mag(f46[bin + 1]);
      final var1 = mag * 2 - before - after;
      final var2 = (after - before) * 32 / var1;
      final corrected = (bin * 64 + _asI32(var2)) & 0xffff;
      final hz = corrected * (16000 / 2 / 1024 / 64);
      final band = switch (hz.truncate()) {
        >= 250 && <= 519 => 0,
        >= 520 && <= 1449 => 1,
        >= 1450 && <= 3499 => 2,
        >= 3500 && <= 5500 => 3,
        _ => -1,
      };
      if (band < 0) continue;
      bands[band].add(
        FrequencyPeak(_spreadDone - 46, mag.truncate() & 0xffff, corrected),
      );
    }
  }
}

/// In-place radix-2 FFT of 2048 points.
abstract final class _Fft {
  static const n = 2048;
  static final _cos = Float64List.fromList([
    for (var i = 0; i < n ~/ 2; i++) math.cos(-2 * math.pi * i / n),
  ]);
  static final _sin = Float64List.fromList([
    for (var i = 0; i < n ~/ 2; i++) math.sin(-2 * math.pi * i / n),
  ]);
  static final _rev = Int32List.fromList([
    for (var i = 0; i < n; i++) _reverse(i),
  ]);

  static int _reverse(int i) {
    var r = 0;
    for (var b = 0; b < 11; b++) {
      r = (r << 1) | ((i >> b) & 1);
    }
    return r;
  }

  static void transform(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i], ti = im[i];
        re[i] = re[j];
        im[i] = im[j];
        re[j] = tr;
        im[j] = ti;
      }
    }
    for (var size = 2; size <= n; size <<= 1) {
      final half = size >> 1, step = n ~/ size;
      for (var start = 0; start < n; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step], wi = _sin[k * step];
          final a = start + k, b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
  }
}
