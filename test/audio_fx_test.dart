import 'package:flutter_test/flutter_test.dart';
import 'package:segue/core/player/audio_fx.dart';

void main() {
  test('neutral settings produce no filters', () {
    const fx = AudioFx();
    expect(fx.isNeutral, isTrue);
    expect(fx.mpvFilters, '');
    expect(fx.mpvSpeed, 1);
  });

  test('EQ only includes non-zero bands, and only when enabled', () {
    final gains = List<double>.filled(10, 0)
      ..[0] = 6
      ..[5] = -3;
    expect(AudioFx(gains: gains).mpvFilters, '', reason: 'EQ off');
    final f = AudioFx(eqOn: true, gains: gains).mpvFilters;
    expect(
      f,
      'lavfi=[equalizer=f=32:t=o:w=1:g=6.0],'
      'lavfi=[equalizer=f=1000:t=o:w=1:g=-3.0]',
    );
  });

  test('pitch shifts speed and tempo is corrected back', () {
    const fx = AudioFx(semitones: 12);
    expect(fx.mpvSpeed, closeTo(2, 1e-9));
    expect(fx.mpvFilters, 'scaletempo=scale=0.500000');
    // Faster playback with no pitch change: only tempo.
    expect(const AudioFx(speed: 1.25).mpvFilters, 'scaletempo=scale=1.250000');
    // Both: net tempo = speed.
    const both = AudioFx(speed: 1.5, semitones: 12);
    expect(
      both.mpvSpeed * double.parse(both.mpvFilters.split('=').last),
      closeTo(1.5, 1e-6),
    );
    // Tempo correction always comes after the EQ graphs.
    final mixed = AudioFx(
      eqOn: true,
      gains: List<double>.filled(10, 0)..[0] = 3,
      speed: 1.2,
    ).mpvFilters;
    expect(mixed.indexOf('scaletempo'), greaterThan(mixed.indexOf('lavfi')));
  });

  test('json round trip', () {
    final fx = AudioFx(
      eqOn: true,
      gains: AudioFx.presets['Бас']!,
      preset: 'Бас',
      speed: 1.1,
      semitones: -2,
    );
    final back = AudioFx.fromJson(fx.toJson());
    expect(back.mpvFilters, fx.mpvFilters);
    expect(back.preset, 'Бас');
  });
}
