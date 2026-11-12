import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/audio_fx.dart';
import '../../core/player/player.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'motion.dart';

import 'package:segue/core/l10n/l10n.dart';

/// Equalizer (10 bands + presets), speed and pitch.
class SoundPanel extends ConsumerWidget {
  const SoundPanel({super.key});

  static String _hz(int f) => f >= 1000 ? '{0}к'.trArgs([f ~/ 1000]) : '$f';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = ref.watch(audioFxProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final n = ref.read(audioFxProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Эквалайзер'.tr,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Switch(
              value: fx.eqOn,
              onChanged: (v) => n.update((x) => x.copyWith(eqOn: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          duration: SegueMotion.medium,
          opacity: fx.eqOn ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !fx.eqOn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final e in AudioFx.presets.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: PressScale(
                            onTap: () => n.update(
                              (x) => x.copyWith(gains: e.value, preset: e.key),
                            ),
                            child: AnimatedContainer(
                              duration: SegueMotion.medium,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: fx.preset == e.key
                                    ? accent.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.06),
                                border: Border.all(
                                  color: fx.preset == e.key
                                      ? accent
                                      : Colors.transparent,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                e.key.tr,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: fx.preset == e.key
                                      ? accent
                                      : SegueColors.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: Row(
                    children: [
                      for (var i = 0; i < AudioFx.bands.length; i++)
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '${fx.gains[i] > 0 ? '+' : ''}${fx.gains[i].round()}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SegueColors.textDim,
                                ),
                              ),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: accent,
                                      thumbColor: Colors.white,
                                      trackHeight: 4,
                                    ),
                                    child: Slider(
                                      value: fx.gains[i],
                                      min: -12,
                                      max: 12,
                                      onChanged: (v) => n.update((x) {
                                        final g = [...x.gains]
                                          ..[i] = v.roundToDouble();
                                        return x.copyWith(
                                          gains: g,
                                          preset: 'Свой',
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                _hz(AudioFx.bands[i]),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SegueColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Row(
          title: 'Скорость'.tr,
          value: '×${fx.speed.toStringAsFixed(2)}',
          slider: Slider(
            value: fx.speed,
            min: 0.5,
            max: 2,
            divisions: 30,
            onChanged: (v) => n.update((x) => x.copyWith(speed: v)),
          ),
          onReset: fx.speed == 1
              ? null
              : () => n.update((x) => x.copyWith(speed: 1)),
        ),
        _Row(
          title: 'Тон'.tr,
          value: '{0}{1} полутон'.trArgs([
            fx.semitones > 0 ? '+' : '',
            fx.semitones.round(),
          ]),
          slider: Slider(
            value: fx.semitones,
            min: -6,
            max: 6,
            divisions: 12,
            onChanged: (v) =>
                n.update((x) => x.copyWith(semitones: v.roundToDouble())),
          ),
          onReset: fx.semitones == 0
              ? null
              : () => n.update((x) => x.copyWith(semitones: 0)),
        ),
        const SizedBox(height: 4),
        Text(
          'Скорость меняет темп без изменения тона, тон — без изменения темпа.'
              .tr,
          style: TextStyle(color: SegueColors.textDim, fontSize: 12.5),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.value,
    required this.slider,
    this.onReset,
  });

  final String title;
  final String value;
  final Widget slider;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: slider),
        SizedBox(
          width: 92,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: SegueColors.textDim),
          ),
        ),
        IconButton(
          tooltip: 'Сбросить'.tr,
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded, size: 20),
        ),
      ],
    );
  }
}

/// Bottom sheet with the sound panel (from the player).
Future<void> showSoundSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 620),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => const SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [SleepTimerPanel(), SizedBox(height: 18), SoundPanel()],
      ),
    ),
  ),
);

/// Sleep timer: stop the music after a while (fading out) or at the end of
/// the current track.
class SleepTimerPanel extends ConsumerStatefulWidget {
  const SleepTimerPanel({super.key});

  @override
  ConsumerState<SleepTimerPanel> createState() => _SleepTimerPanelState();
}

class _SleepTimerPanelState extends ConsumerState<SleepTimerPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps the countdown fresh.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(playerProvider).sleepAt.value != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: Listenable.merge([player.sleepAt, player.sleepAfterTrack]),
      builder: (context, _) {
        final at = player.sleepAt.value;
        final endOfTrack = player.sleepAfterTrack.value;
        final left = at?.difference(DateTime.now());
        String status = 'Музыка сама затихнет и остановится'.tr;
        if (endOfTrack) status = 'Остановится в конце этого трека'.tr;
        if (left != null && !left.isNegative) {
          final m = left.inMinutes, sec = left.inSeconds % 60;
          status = 'Остановится через {0}:{1}'.trArgs([
            m,
            sec.toString().padLeft(2, '0'),
          ]);
        }
        Widget chip(String label, bool on, VoidCallback onTap) => PressScale(
          onTap: onTap,
          child: AnimatedContainer(
            duration: SegueMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? accent : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: on ? SegueColors.ink : SegueColors.text,
              ),
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Таймер сна'.tr,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: const TextStyle(color: SegueColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(
                  'Выкл'.tr,
                  at == null && !endOfTrack,
                  () => player.setSleepTimer(null),
                ),
                for (final m in const [15, 30, 45, 60])
                  chip('{0} мин'.trArgs([m]), _minutes == m && at != null, () {
                    _minutes = m;
                    player.setSleepTimer(Duration(minutes: m));
                  }),
                chip(
                  'До конца трека'.tr,
                  endOfTrack,
                  () => player.setSleepTimer(null, endOfTrack: true),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  int _minutes = 0;
}
