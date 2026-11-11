import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/library/library.dart';
import '../../core/library/library_store.dart';
import '../../core/sync/sync.dart';
import '../../core/sync/sync_service.dart';
import '../theme/theme.dart';
import '../widgets/nav.dart';

IconData platformIcon(String os) => switch (os) {
  'android' || 'ios' => Icons.smartphone_rounded,
  'macos' => Icons.laptop_mac_rounded,
  'windows' || 'linux' => Icons.computer_rounded,
  _ => Icons.devices_other_rounded,
};

/// Paired devices, pairing by code, and moving playback between devices.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  static const routeName = '/devices';

  static Route<void> route() => MaterialPageRoute(
    settings: const RouteSettings(name: routeName),
    builder: (_) => const DevicesScreen(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final peers = ref.watch(peersProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListenableBuilder(
            listenable: Listenable.merge([
              sync.nearby,
              sync.syncing,
              sync.lastSync,
            ]),
            builder: (context, _) {
              final unpaired = [
                for (final d in sync.nearby.value.values)
                  if (!peers.any((p) => p.id == d.id)) d,
              ];
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: Text(
                      'Устройства',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 6, 18),
                    child: Text(
                      'Любимые, плейлисты и история синхронизируются между твоими устройствами '
                      'в одной Wi-Fi-сети — напрямую, без облака и аккаунта.',
                      style: TextStyle(color: SegueColors.textDim, height: 1.4),
                    ),
                  ),
                  _ThisDevice(sync: sync),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => showJoinByCode(context, sync),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Войти по коду'),
                      ),
                      if (ScanScreen.supported)
                        OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ScanScreen(),
                                ),
                              ),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Сканировать QR'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (peers.isNotEmpty) ...[
                    const _Header('Связанные'),
                    for (final p in peers) _PeerCard(peer: p, sync: sync),
                  ],
                  const _Header('Рядом в сети'),
                  if (unpaired.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Text(
                        'Открой Segue на другом устройстве в этой же Wi-Fi-сети — оно появится здесь.',
                        style: TextStyle(color: SegueColors.textDim),
                      ),
                    )
                  else
                    for (final d in unpaired)
                      _Card(
                        icon: platformIcon(d.platform),
                        title: d.name,
                        subtitle: 'Не связано',
                        trailing: FilledButton(
                          onPressed: () => _pairWith(context, sync, d),
                          child: const Text('Связать'),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pairWith(
    BuildContext context,
    SyncService sync,
    NearbyDevice d,
  ) async {
    final controller = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: SegueColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text('Связать с «${d.name}»'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'На том устройстве открой «Устройства» → «Показать код» и введи его здесь.',
                style: TextStyle(color: SegueColors.textDim, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 10,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFFF8A80)),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await sync.pair(d, controller.text);
                  if (dialog.mounted) Navigator.pop(dialog);
                } on SyncException catch (e) {
                  setState(() => error = e.message);
                } catch (_) {
                  setState(() => error = 'Не удалось связаться с устройством');
                }
              },
              child: const Text('Связать'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThisDevice extends StatelessWidget {
  const _ThisDevice({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: sync.pairingCode,
      builder: (context, code, _) => AnimatedContainer(
        duration: SegueMotion.medium,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              SegueColors.accent.withValues(alpha: code == null ? 0.12 : 0.26),
              const Color(0xFF8E5CFF).withValues(alpha: 0.14),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(platformIcon(sync.platform), size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sync.deviceName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Это устройство',
                        style: TextStyle(color: SegueColors.textDim),
                      ),
                    ],
                  ),
                ),
                if (code == null)
                  FilledButton.tonal(
                    onPressed: sync.openPairing,
                    child: const Text('Показать код'),
                  )
                else
                  TextButton(
                    onPressed: sync.closePairing,
                    child: const Text('Скрыть'),
                  ),
              ],
            ),
            AnimatedSize(
              duration: SegueMotion.medium,
              curve: SegueMotion.ease,
              child: code == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _CodeAndQr(sync: sync, code: code),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pairing code next to a QR code with the same thing (scan with the
/// Segue app on a phone).
class _CodeAndQr extends StatelessWidget {
  const _CodeAndQr({required this.sync, required this.code});

  final SyncService sync;
  final String code;

  @override
  Widget build(BuildContext context) {
    final codeText = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${code.substring(0, 3)} ${code.substring(3)}',
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'На другом устройстве: «Войти по коду»\nили отсканируй QR в Segue. Код действует 3 минуты',
          textAlign: TextAlign.center,
          style: TextStyle(color: SegueColors.textDim, height: 1.4),
        ),
      ],
    );
    final qr = FutureBuilder<String?>(
      future: sync.pairingLink(),
      builder: (context, snap) => snap.data == null
          ? const SizedBox(width: 168, height: 168)
          : Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                // Dark on white scans reliably with any camera.
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: snap.data!,
                size: 148,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: SegueColors.ink,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: SegueColors.ink,
                ),
              ),
            ),
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth > 460
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Flexible(child: codeText),
                qr,
              ],
            )
          : Column(children: [qr, const SizedBox(height: 16), codeText]),
    );
  }
}

/// "Log in" on a new device: type the code shown on another one.
Future<void> showJoinByCode(BuildContext context, SyncService sync) async {
  final controller = TextEditingController();
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: SegueColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Войти по коду'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'На устройстве, где уже есть твоя музыка, открой «Устройства» → «Показать код».',
              style: TextStyle(color: SegueColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !busy,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: 10,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialog),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final peer = await sync.joinWithCode(controller.text);
                      if (dialog.mounted) Navigator.pop(dialog);
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Готово: музыка с «${peer.name}» теперь и здесь',
                            ),
                          ),
                        );
                      }
                    } on SyncException catch (e) {
                      setState(() => error = e.message);
                    } finally {
                      if (dialog.mounted) setState(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Войти'),
          ),
        ],
      ),
    ),
  );
}

/// Camera QR scanner (phones): scans the code shown on another device.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (_busy || value == null || !value.startsWith('segue://')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final peer = await ref.read(syncProvider).joinWithLink(value);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Готово: музыка с «${peer.name}» теперь и здесь'),
        ),
      );
    } on SyncException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Не удалось связаться. Устройства в одной сети?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Сканировать QR'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _busy
                  ? 'Подключаемся…'
                  : (_error ?? 'Наведи камеру на QR-код на другом устройстве'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _error != null ? const Color(0xFFFF8A80) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.peer, required this.sync});

  final Peer peer;
  final SyncService sync;

  String _ago(DateTime? t) {
    if (t == null) return 'ещё не синхронизировано';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'синхронизировано только что';
    if (d.inMinutes < 60) return 'синхронизировано ${d.inMinutes} мин назад';
    return 'синхронизировано в ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String ok,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(ok)));
    } on SyncException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text('${peer.name} не отвечает')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = sync.isOnline(peer.id);
    final busy = sync.syncing.value.contains(peer.id);
    return _Card(
      icon: platformIcon(peer.platform),
      title: peer.name,
      subtitleWidget: Row(
        children: [
          AnimatedContainer(
            duration: SegueMotion.medium,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF5BD68A) : SegueColors.textDim,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              online ? _ago(sync.lastSync.value[peer.id]) : 'не в сети',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: SegueColors.textDim, fontSize: 13),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Синхронизировать',
            onPressed: online && !busy
                ? () => _run(
                    context,
                    () => sync.syncWith(peer.id),
                    'Синхронизировано с ${peer.name}',
                  )
                : null,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            color: SegueColors.surfaceHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (v) => switch (v) {
              'take' => _run(
                context,
                () => sync.takePlayback(peer.id),
                'Музыка с ${peer.name} играет здесь',
              ),
              'send' => _run(
                context,
                () => sync.sendPlayback(peer.id),
                'Музыка продолжается на ${peer.name}',
              ),
              _ => sync.unpair(peer.id),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'take',
                enabled: online,
                child: const Text('Слушать здесь то, что играет там'),
              ),
              PopupMenuItem(
                value: 'send',
                enabled: online,
                child: const Text('Продолжить на этом устройстве'),
              ),
              const PopupMenuItem(value: 'unpair', child: Text('Отвязать')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
        color: SegueColors.textDim,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                subtitleWidget ??
                    Text(
                      subtitle ?? '',
                      style: const TextStyle(
                        color: SegueColors.textDim,
                        fontSize: 13,
                      ),
                    ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Bottom sheet from the player: move playback to / from a device.
Future<void> showHandoffSheet(BuildContext context, WidgetRef ref) {
  final sync = ref.read(syncProvider);
  final peers = ref.read(libraryProvider).peers();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: SegueColors.surface,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: ValueListenableBuilder(
          valueListenable: sync.nearby,
          builder: (context, _, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Продолжить на устройстве',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              if (peers.isEmpty)
                ListTile(
                  leading: const Icon(Icons.add_link_rounded),
                  title: const Text('Связать устройство'),
                  subtitle: const Text(
                    'Телефон, ноутбук или ПК с Segue в этой сети',
                    style: TextStyle(color: SegueColors.textDim),
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    pushUnique(
                      Navigator.of(context, rootNavigator: true),
                      DevicesScreen.route(),
                    );
                  },
                ),
              for (final p in peers)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  enabled: sync.isOnline(p.id),
                  leading: Icon(platformIcon(p.platform)),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    sync.isOnline(p.id)
                        ? 'Нажми — и музыка продолжится там'
                        : 'Не в сети',
                    style: const TextStyle(color: SegueColors.textDim),
                  ),
                  trailing: sync.isOnline(p.id)
                      ? IconButton(
                          tooltip: 'Забрать музыку оттуда',
                          icon: const Icon(Icons.download_rounded),
                          onPressed: () async {
                            Navigator.pop(sheet);
                            await _report(
                              context,
                              () => sync.takePlayback(p.id),
                              'Играет здесь',
                            );
                          },
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(sheet);
                    await _report(
                      context,
                      () => sync.sendPlayback(p.id),
                      'Продолжается на ${p.name}',
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _report(
  BuildContext context,
  Future<void> Function() action,
  String ok,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    messenger?.showSnackBar(SnackBar(content: Text(ok)));
  } on SyncException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Устройство не отвечает')),
    );
  }
}
