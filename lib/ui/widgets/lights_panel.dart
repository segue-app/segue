import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/lights/light_devices.dart';
import '../../core/lights/light_sync.dart';
import '../theme/theme.dart';

/// Settings: lights in time with the music.
class LightsPanel extends ConsumerWidget {
  const LightsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lights = ref.watch(lightSyncProvider);
    if (lights == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([lights.enabled, lights.devices]),
      builder: (context, _) {
        final on = lights.enabled.value;
        final devices = lights.devices.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              title: Text(
                'Свет в такт'.tr,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Ленты, лампы и RGB-подсветка компьютера вспыхивают на ударах. Удары известны заранее, поэтому свет приходит вместе с ними, а не после'
                    .tr,
                style: const TextStyle(color: SegueColors.textDim),
              ),
              trailing: Switch(
                value: on,
                onChanged: (v) => lights.setEnabled(v),
              ),
            ),
            if (on) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                child: SegmentedButton<LightEffect>(
                  segments: [
                    ButtonSegment(
                      value: LightEffect.pulse,
                      label: Text('Пульс'.tr),
                      icon: const Icon(Icons.flash_on_rounded),
                    ),
                    ButtonSegment(
                      value: LightEffect.bars,
                      label: Text('Цвет на такт'.tr),
                      icon: const Icon(Icons.palette_rounded),
                    ),
                  ],
                  selected: {lights.effect},
                  onSelectionChanged: (v) => lights.setEffect(v.first),
                ),
              ),
              _Latency(lights: lights),
              for (final d in devices)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(_icon(d.kind)),
                  title: Text('${_name(d.kind)} · ${d.address}'),
                  subtitle: Text(
                    d.status.startsWith('error')
                        ? 'Не отвечает: проверь адрес и что устройство в той же сети'
                              .tr
                        : d.status,
                    style: TextStyle(
                      color: d.status.startsWith('error')
                          ? Colors.redAccent
                          : SegueColors.textDim,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить'.tr,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => lights.remove(d),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.linear_scale_rounded),
                      label: const Text('WLED'),
                      onPressed: () async {
                        final ip = await _ask(
                          context,
                          'Адрес ленты WLED'.tr,
                          '192.168.1.40',
                        );
                        if (ip != null) await lights.add(WledDevice(ip));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lightbulb_outline_rounded),
                      label: const Text('Govee'),
                      onPressed: () => _govee(context, lights),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.keyboard_rounded),
                      label: const Text('OpenRGB'),
                      onPressed: () async {
                        final a = await _ask(
                          context,
                          'Адрес сервера OpenRGB'.tr,
                          '127.0.0.1:6742',
                          initial: '127.0.0.1:6742',
                        );
                        if (a != null) await lights.add(OpenRgbDevice(a));
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(
                  'OpenRGB управляет подсветкой клавиатур, мышей и ПК почти всех марок: включи в нём «SDK Server». Govee: включи «LAN Control» в приложении Govee.'
                      .tr,
                  style: const TextStyle(
                    color: SegueColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    'wled' => Icons.linear_scale_rounded,
    'govee' => Icons.lightbulb_outline_rounded,
    _ => Icons.keyboard_rounded,
  };

  static String _name(String kind) => switch (kind) {
    'wled' => 'WLED',
    'govee' => 'Govee',
    _ => 'OpenRGB',
  };

  Future<void> _govee(BuildContext context, LightSync lights) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text('Ищу Govee в сети…'.tr)));
    final found = await GoveeDevice.scan();
    final known = {for (final d in lights.devices.value) d.address};
    final fresh = found.where((ip) => !known.contains(ip)).toList();
    for (final ip in fresh) {
      await lights.add(GoveeDevice(ip));
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          fresh.isEmpty
              ? 'Govee не нашлись. Включи «LAN Control» в приложении Govee'.tr
              : 'Добавлено: {0}'.trArgs([fresh.length]),
        ),
      ),
    );
  }

  static Future<String?> _ask(
    BuildContext context,
    String title,
    String hint, {
    String initial = '',
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) =>
              Navigator.pop(d, v.trim().isEmpty ? null : v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text('Отмена'.tr),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()),
            child: Text('Добавить'.tr),
          ),
        ],
      ),
    );
  }
}

class _Latency extends StatefulWidget {
  const _Latency({required this.lights});

  final LightSync lights;

  @override
  State<_Latency> createState() => _LatencyState();
}

class _LatencyState extends State<_Latency> {
  late double _v = widget.lights.latencyMs.toDouble();

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    title: Text('Сдвиг света'.tr),
    subtitle: Text(
      'Если свет спешит или опаздывает: с Bluetooth-колонками звук идёт позже'
          .tr,
      style: const TextStyle(color: SegueColors.textDim, fontSize: 12.5),
    ),
    trailing: SizedBox(
      width: 230,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: _v,
              min: 0,
              max: 400,
              divisions: 40,
              onChanged: (v) => setState(() => _v = v),
              onChangeEnd: (v) => widget.lights.setLatency(v.round()),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '{0} мс'.trArgs([_v.round()]),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    ),
  );
}
