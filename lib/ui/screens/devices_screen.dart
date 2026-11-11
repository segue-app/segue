import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/sync/connect.dart';
import '../../core/sync/relay.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import '../widgets/artwork.dart';
import '../widgets/motion.dart';

IconData platformIcon(String os) => switch (os) {
  'android' || 'ios' => Icons.smartphone_rounded,
  'macos' => Icons.laptop_mac_rounded,
  'windows' || 'linux' => Icons.computer_rounded,
  _ => Icons.devices_other_rounded,
};

/// The track a remote device plays, if any.
Track? remoteTrack(RemoteDevice? d) {
  final j = d?.track;
  if (j == null) return null;
  try {
    return Track.fromJson(j);
  } catch (_) {
    return null;
  }
}

/// This user's devices: add one (code / QR), see what plays where, move
/// the music and control it remotely.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  static const routeName = '/devices';

  static Route<void> route() => MaterialPageRoute(
    settings: const RouteSettings(name: routeName),
    builder: (_) => const DevicesScreen(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([connect.changes, connect.inviteCode]),
          builder: (context, _) {
            final devices = connect.devices();
            final online = connect.relay.connected.value;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(6, 8, 6, 6),
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
                      padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
                      child: Text(
                        'Любимые, плейлисты и история — на всех твоих '
                        'устройствах, в любой сети. Музыку можно переносить '
                        'и управлять ею с телефона, как пультом.',
                        style: TextStyle(color: SegueColors.textDim),
                      ),
                    ),
                    _Status(online: online),
                    const SizedBox(height: 14),
                    const _ThisDevice(),
                    if (devices.isNotEmpty) ...[
                      const _Header('Мои устройства'),
                      for (final d in devices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DeviceCard(device: d),
                        ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => _confirmLeave(context, connect),
                          child: const Text(
                            'Отключить это устройство от остальных',
                            style: TextStyle(color: SegueColors.textDim),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static Future<void> _confirmLeave(BuildContext context, Connect c) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (d) => AlertDialog(
        backgroundColor: SegueColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Отключить это устройство?'),
        content: const Text(
          'Оно перестанет синхронизироваться с остальными. Музыка, лайки и '
          'плейлисты здесь останутся. Связать снова можно по новому коду.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (ok == true) await c.leave();
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF5BD68A) : SegueColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              online ? 'Синхронизация через интернет включена · зашифровано' : 'Нет связи с интернетом — синхронизация только в этой Wi-Fi-сети',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThisDevice extends ConsumerWidget {
  const _ThisDevice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    final code = connect.inviteCode.value;
    final accent = ref.watch(currentColorsProvider).accent;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DeviceIcon(os: Platform.operatingSystem, color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Это устройство',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      connect.sync.deviceName,
                      style: const TextStyle(color: SegueColors.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: SegueMotion.medium,
            curve: SegueMotion.ease,
            child: code != null
                ? _Invite(code: code)
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: SegueColors.ink,
                        ),
                        onPressed: () => connect.openInvite(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text(
                          'Добавить устройство',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showJoinDialog(context),
                        icon: const Icon(Icons.password_rounded),
                        label: const Text('Войти по коду'),
                      ),
                      if (ScanScreen.supported)
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).push(ScanScreen.route()),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Сканировать QR'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The code and QR another device uses to join.
class _Invite extends ConsumerWidget {
  const _Invite({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    final pretty = '${code.substring(0, 4)}-${code.substring(4)}';
    final qr = FutureBuilder<String>(
      future: connect.inviteLink(code),
      builder: (context, link) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: link.hasData
            ? QrImageView(data: link.data!, size: 168, padding: EdgeInsets.zero)
            : const SizedBox.square(dimension: 168),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Код для другого устройства',
          style: TextStyle(color: SegueColors.textDim),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => Clipboard.setData(ClipboardData(text: pretty)),
          child: Text(
            pretty,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'На другом устройстве открой Segue → «Устройства» → «Войти по коду» '
          'или отсканируй QR. Работает в любой сети. Код действует 10 минут.',
          style: TextStyle(color: SegueColors.textDim, fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: connect.closeInvite, child: const Text('Готово')),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth > 480
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                qr,
                const SizedBox(width: 20),
                Expanded(child: text),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [qr, const SizedBox(height: 14), text],
            ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});
  final MyDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final localPlaying = ref.watch(playingProvider).value ?? false;
    final d = device;
    final track = remoteTrack(d.remote);
    final status = !d.online
        ? 'Не в сети'
        : d.playing && track != null
        ? 'Играет: ${track.title} — ${track.artist}'
        : 'В сети';

    Future<void> run(Future<void> Function() f, String done) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await f();
        messenger?.showSnackBar(SnackBar(content: Text(done)));
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('$e')));
      }
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  _DeviceIcon(
                    os: d.platform,
                    color: d.online ? Colors.white : SegueColors.textDim,
                  ),
                  if (d.online)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5BD68A),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SegueColors.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: d.playing ? accent : SegueColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              if (track != null && d.playing)
                Artwork(url: track.artworkUrl, size: 44, radius: 10),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: SegueColors.textDim,
                ),
                onSelected: (_) => connect.forget(d.id),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'forget',
                    child: Text('Убрать из списка'),
                  ),
                ],
              ),
            ],
          ),
          if (d.online) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (d.playing) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => run(
                      () => connect.takeFrom(d.id),
                      'Музыка с ${d.name} играет здесь',
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Слушать здесь'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showRemoteControl(context, d.id),
                    icon: const Icon(Icons.settings_remote_rounded),
                    label: const Text('Пульт'),
                  ),
                ],
                if (localPlaying)
                  OutlinedButton.icon(
                    onPressed: () => run(
                      () => connect.handOffTo(d.id),
                      'Музыка продолжается на ${d.name}',
                    ),
                    icon: const Icon(Icons.upload_rounded),
                    label: Text('Включить на ${d.name}'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceIcon extends StatelessWidget {
  const _DeviceIcon({required this.os, required this.color});
  final String os;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(platformIcon(os), color: color),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 24, 6, 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: SegueColors.line),
    ),
    child: child,
  );
}

// --- join -------------------------------------------------------------------

Future<void> showJoinDialog(BuildContext context) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  builder: (_) => const _JoinDialog(),
);

class _JoinDialog extends ConsumerStatefulWidget {
  const _JoinDialog();

  @override
  ConsumerState<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends ConsumerState<_JoinDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final name = await ref.read(connectProvider).join(_code.text);
      if (!mounted) return;
      Navigator.pop(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Готово: связано с «$name». Музыка уже едет')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SegueColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Войти по коду'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'На устройстве, где уже есть твоя музыка: «Устройства» → '
              '«Добавить устройство». Введи код оттуда.',
              style: TextStyle(color: SegueColors.textDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(hintText: 'ABCD-EFGH'),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(9),
              ],
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Связываем…' : 'Войти'),
        ),
      ],
    );
  }
}

// --- QR scanner ---------------------------------------------------------------

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  static bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const ScanScreen());

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !raw.startsWith('segue://')) {
      if (raw != null) setState(() => _error = 'Это не QR-код Segue');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final name = await ref.read(connectProvider).join(raw);
      if (!mounted) return;
      Navigator.pop(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Готово: связано с «$name». Музыка уже едет')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Сканировать QR'),
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // Frame to aim with.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _busy
                    ? 'Связываем…'
                    : (_error ??
                          'Наведи камеру на QR-код в «Устройства» → '
                              '«Добавить устройство» на другом устройстве'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- "where to play" ------------------------------------------------------------

/// Spotify-style device picker: what plays where, and moving it.
Future<void> showHandoffSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SegueColors.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _WhereToPlay(),
    );

class _WhereToPlay extends ConsumerWidget {
  const _WhereToPlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connect = ref.read(connectProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final localPlaying = ref.watch(playingProvider).value ?? false;
    return ListenableBuilder(
      listenable: connect.changes,
      builder: (context, _) {
        final devices = connect.devices().where((d) => d.online).toList();
        final elsewhere = devices.where((d) => d.playing).firstOrNull;
        final hereActive = localPlaying || elsewhere == null;

        Widget tile({
          required IconData icon,
          required String title,
          required String subtitle,
          required bool active,
          required VoidCallback? onTap,
        }) => ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(icon, color: active ? accent : Colors.white),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: active ? accent : SegueColors.text,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: SegueColors.textDim),
          ),
          trailing: active
              ? Icon(Icons.graphic_eq_rounded, color: accent)
              : null,
          onTap: onTap,
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text(
                    'Где играть',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                tile(
                  icon: platformIcon(Platform.operatingSystem),
                  title: 'Это устройство',
                  subtitle: hereActive
                      ? 'Играет здесь'
                      : 'Нажми, чтобы слушать здесь',
                  active: hereActive,
                  onTap: hereActive
                      ? null
                      : () {
                          Navigator.pop(context);
                          connect.takeFrom(elsewhere.id);
                        },
                ),
                for (final d in devices)
                  tile(
                    icon: platformIcon(d.platform),
                    title: d.name,
                    subtitle: d.playing
                        ? 'Играет: ${remoteTrack(d.remote)?.title ?? ''}'
                        : 'В сети',
                    active: d.playing && !localPlaying,
                    onTap: () {
                      Navigator.pop(context);
                      if (localPlaying) {
                        connect.handOffTo(d.id);
                      } else if (d.playing) {
                        showRemoteControl(context, d.id);
                      }
                    },
                  ),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Других устройств в сети нет. Добавь их в «Устройства».',
                      style: TextStyle(color: SegueColors.textDim),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- remote control --------------------------------------------------------------

/// A remote for the music playing on another device.
Future<void> showRemoteControl(BuildContext context, String deviceId) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SegueColors.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => RemoteControl(deviceId: deviceId),
    );

class RemoteControl extends ConsumerStatefulWidget {
  const RemoteControl({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<RemoteControl> createState() => _RemoteControlState();
}

class _RemoteControlState extends ConsumerState<RemoteControl> {
  Timer? _tick;
  double? _dragVolume;

  @override
  void initState() {
    super.initState();
    // The position moves on between state messages.
    _tick = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connect = ref.read(connectProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: connect.relay.devices,
      builder: (context, _) {
        final d = connect.relay.devices.value[widget.deviceId];
        final track = remoteTrack(d);
        void cmd(String op, [Map<String, dynamic>? a]) =>
            connect.command(widget.deviceId, op, a);
        if (d == null || track == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: Text('Там сейчас ничего не играет')),
          );
        }
        final pos = d.position;
        final total = d.duration;
        final f = total == null || total.inMilliseconds == 0
            ? 0.0
            : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(platformIcon(d.platform), size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Играет на ${d.name}',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Artwork(url: track.artworkUrl, size: 220, radius: 24),
                const SizedBox(height: 18),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  track.artist,
                  style: const TextStyle(color: SegueColors.textDim),
                ),
                const SizedBox(height: 10),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: accent,
                    thumbColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Slider(
                    value: f,
                    onChanged: total == null ? null : (_) {},
                    onChangeEnd: (v) => cmd('seek', {
                      'ms': (total!.inMilliseconds * v).round(),
                    }),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(pos), style: _time),
                    Text(formatDuration(total), style: _time),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 36,
                      onPressed: () => cmd('prev'),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: 12),
                    PressScale(
                      onTap: () => cmd(d.playing ? 'pause' : 'play'),
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          d.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 38,
                          color: SegueColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      iconSize: 36,
                      onPressed: () => cmd('next'),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.volume_down_rounded,
                      color: SegueColors.textDim,
                    ),
                    Expanded(
                      child: Slider(
                        value: _dragVolume ?? d.volume.clamp(0.0, 1.0),
                        onChanged: (v) => setState(() => _dragVolume = v),
                        onChangeEnd: (v) {
                          cmd('volume', {'v': v});
                          // Keep showing it until their state confirms.
                          Future<void>.delayed(
                            const Duration(seconds: 2),
                            () => mounted
                                ? setState(() => _dragVolume = null)
                                : null,
                          );
                        },
                      ),
                    ),
                    const Icon(
                      Icons.volume_up_rounded,
                      color: SegueColors.textDim,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    connect.takeFrom(widget.deviceId);
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Слушать на этом устройстве'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _time = TextStyle(
    color: SegueColors.textDim,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
