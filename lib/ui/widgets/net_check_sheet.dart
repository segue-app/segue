import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diag/net_check.dart';
import '../../core/integrations/updates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sources/sources.dart';
import '../theme/theme.dart';

/// Checks every service from this network and says what a VPN would fix.
Future<void> showNetCheckSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => const _NetCheckSheet(),
);

class _NetCheckSheet extends ConsumerStatefulWidget {
  const _NetCheckSheet();

  @override
  ConsumerState<_NetCheckSheet> createState() => _NetCheckSheetState();
}

class _NetCheckSheetState extends ConsumerState<_NetCheckSheet> {
  final _results = <String, NetResult>{};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    await NetCheck(sources: ref.read(sourcesProvider)).run(
      onResult: (r) {
        if (mounted) setState(() => _results[r.name] = r);
      },
    );
    if (mounted) setState(() => _running = false);
  }

  bool _failed(String name) => _results[name]?.ok == false;

  /// What to do about what failed, in plain words.
  List<String> _advice() => [
    if (_failed(NetCheck.names[0]) || _failed(NetCheck.names[1]))
      'YouTube не открывается из этой сети: в некоторых странах (например, в России) он заблокирован или замедлен. Без него не играет большая часть треков. Помогает VPN.'
          .tr,
    if (_failed(NetCheck.names[2]))
      'SoundCloud недоступен из этой сети. Треки с него не будут играть.'.tr,
    if (_failed(NetCheck.names[3]))
      'Яндекс Музыка пускает только из России и Беларуси: для импорта включи VPN с сервером там.'
          .tr,
    if (_results.length == NetCheck.names.length &&
        _results.values.every((r) => !r.ok))
      'Не отвечает ничего: похоже, нет интернета.'.tr,
  ];

  String _report() => [
    'Segue $appVersion · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    for (final n in NetCheck.names) '${_results[n] ?? '…  $n'}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final advice = _advice();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Проверка связи'.tr,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Что открывается из твоей сети прямо сейчас'.tr,
              style: const TextStyle(color: SegueColors.textDim),
            ),
            const SizedBox(height: 12),
            for (final n in NetCheck.names) _row(n, _results[n]),
            if (advice.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final a in advice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(a, style: const TextStyle(height: 1.35)),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text('Скопировать отчёт'.tr),
                  onPressed: _running
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _report()));
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(content: Text('Скопировано'.tr)),
                          );
                        },
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _running ? null : _run,
                  child: Text('Проверить снова'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String name, NetResult? r) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 22,
          child: r == null
              ? const Padding(
                  padding: EdgeInsets.all(3),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  r.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 22,
                  color: r.ok ? const Color(0xFF5BD68A) : Colors.redAccent,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.tr,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (r != null && !r.ok && r.error != null)
                Text(
                  r.error!,
                  style: const TextStyle(
                    color: SegueColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
        ),
        if (r?.ms != null)
          Text(
            '{0} мс'.trArgs([r!.ms!]),
            style: const TextStyle(color: SegueColors.textDim, fontSize: 12.5),
          ),
      ],
    ),
  );
}
