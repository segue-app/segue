import 'dart:async';

import '../widgets/content_width.dart';

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
import '../widgets/jam_sheet.dart';

import 'package:segue/core/l10n/l10n.dart';

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
            return WideScroll(
              max: 720,
              builder: (context, side) => ListView(
                padding: EdgeInsets.fromLTRB(16 + side, 12, 16 + side, 32),
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(6, 8, 6, 6),
                    child: Text(
                      'Устройства'.tr,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
                    child: Text(
                      'Любимые, плейлисты и история — на всех твоих устройствах, в любой сети. Музыку можно переносить и управлять ею с телефона, как пультом.'
                          .tr,
                      style: TextStyle(color: SegueColors.textDim),
                    ),
                  ),
                  _Status(online: online),
                  const SizedBox(height: 14),
                  const _ThisDevice(),
                  if (devices.isNotEmpty) ...[
                    _Header('Мои устройства'.tr),
                    for (final d in devices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DeviceCard(device: d),
                      ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => _confirmLeave(context, connect),
                        child: Text(
                          'Отключить это устройство от остальных'.tr,
                          style: TextStyle(color: SegueColors.textDim),
                        ),
                      ),
                    ),
                  ],
                ],
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
        title: Text('Отключить это устройство?'.tr),
        content: Text(
          'Оно перестанет синхронизироваться с остальными. Музыка, лайки и плейлисты здесь останутся. Связать снова можно по новому коду.'
              .tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text('Отмена'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Отключить'.tr),
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
              online
                  ? 'Синхронизация через интернет включена · зашифровано'.tr
                  : 'Нет связи с интернетом — синхронизация только в этой Wi-Fi-сети'
                        .tr,
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
    // Listens itself: as a const child it isn't rebuilt by the screen.
    return ListenableBuilder(
      listenable: Listenable.merge([connect.inviteCode, connect.changes]),
      builder: (context, _) => _build(context, ref, connect),
    );
  }

  Widget _build(BuildContext context, WidgetRef ref, Connect connect) {
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
                    Text(
                      'Это устройство'.tr,
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
                        label: Text(
                          'Добавить устройство'.tr,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showJoinDialog(context),
                        icon: const Icon(Icons.password_rounded),
                        label: Text('Войти по коду'.tr),
                      ),
                      if (ScanScreen.supported)
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                            rootNavigator: true,
                          ).push(ScanScreen.route()),
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: Text('Сканировать QR'.tr),
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
        Text(
          'Код для другого устройства'.tr,
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
        Text(
          'На другом устройстве открой Segue → «Устройства» → «Войти по коду» или отсканируй QR. Работает в любой сети. Код действует 10 минут.'
              .tr,
          style: TextStyle(color: SegueColors.textDim, fontSize: 13),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: connect.closeInvite, child: Text('Готово'.tr)),
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
        ? 'Не в сети'.tr
        : d.playing && track != null
        ? 'Играет: {0} — {1}'.trArgs([track.title, track.artist])
        : 'В сети'.tr;

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
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'forget',
                    child: Text('Убрать из списка'.tr),
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
                if (d.playing || connect.player?.outputId == d.id)
                  FilledButton.tonalIcon(
                    onPressed: () => run(
                      () => connect.player?.outputId == d.id
                          ? connect.playHere()
                          : connect.takeFrom(d.id),
                      'Музыка с {0} играет здесь'.trArgs([d.name]),
                    ),
                    icon: const Icon(Icons.headphones_rounded),
                    label: Text('Слушать здесь'.tr),
                  ),
                if (connect.player?.outputId != d.id &&
                    (localPlaying || connect.player?.current != null))
                  OutlinedButton.icon(
                    onPressed: () => run(
                      () => connect.playOn(d.id),
                      'Играет на {0}. Этот плеер — пульт'.trArgs([d.name]),
                    ),
                    icon: const Icon(Icons.cast_rounded),
                    label: Text('Включить на {0}'.trArgs([d.name])),
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
        SnackBar(
          content: Text(
            'Готово: связано с «{0}». Музыка уже едет'.trArgs([name]),
          ),
        ),
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
      title: Text('Войти по коду'.tr),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'На устройстве, где уже есть твоя музыка: «Устройства» → «Добавить устройство». Введи код оттуда.'
                  .tr,
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
          child: Text('Отмена'.tr),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Связываем…'.tr : 'Войти'.tr),
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
      if (raw != null) setState(() => _error = 'Это не QR-код Segue'.tr);
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
        SnackBar(
          content: Text(
            'Готово: связано с «{0}». Музыка уже едет'.trArgs([name]),
          ),
        ),
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
        title: Text('Сканировать QR'.tr),
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
                    ? 'Связываем…'.tr
                    : (_error ??
                          'Наведи камеру на QR-код в «Устройства» → «Добавить устройство» на другом устройстве'
                              .tr),
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

/// Spotify-style device picker: pick where the music plays. Picking another
/// device moves it there and this player becomes its remote.
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
    final player = ref.read(playerProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: Listenable.merge([connect.changes, player.output]),
      builder: (context, _) {
        final devices = connect.devices().where((d) => d.online).toList();
        final out = player.outputId;
        final messenger = ScaffoldMessenger.maybeOf(context);

        Future<void> pick(Future<void> Function() f, String done) async {
          Navigator.pop(context);
          try {
            await f();
            messenger?.showSnackBar(SnackBar(content: Text(done)));
          } catch (e) {
            messenger?.showSnackBar(
              SnackBar(content: Text('Не получилось: {0}'.trArgs([e]))),
            );
          }
        }

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
          onTap: active ? null : onTap,
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Text(
                    'Где играть'.tr,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                tile(
                  icon: platformIcon(Platform.operatingSystem),
                  title: 'Это устройство'.tr,
                  subtitle: out == null
                      ? 'Музыка играет здесь'.tr
                      : 'Нажми, чтобы музыка играла здесь'.tr,
                  active: out == null,
                  onTap: () => pick(
                    connect.playHere,
                    'Музыка играет на этом устройстве'.tr,
                  ),
                ),
                for (final d in devices)
                  tile(
                    icon: platformIcon(d.platform),
                    title: d.name,
                    subtitle: out == d.id
                        ? 'Играет там · этот плеер — пульт'.tr
                        : d.playing
                        ? 'Играет: {0}'.trArgs([
                            remoteTrack(d.remote)?.title ?? '',
                          ])
                        : 'В сети'.tr,
                    active: out == d.id,
                    onTap: () => pick(
                      () => connect.playOn(d.id),
                      'Играет на {0}. Этот плеер — пульт'.trArgs([d.name]),
                    ),
                  ),
                if (devices.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Других устройств в сети нет. Добавь их в «Устройства».'
                          .tr,
                      style: TextStyle(color: SegueColors.textDim),
                    ),
                  ),
                const Divider(color: SegueColors.line, height: 20),
                tile(
                  icon: Icons.groups_rounded,
                  title: 'Слушать вместе с друзьями'.tr,
                  subtitle: 'Одна музыка у всех, в любой сети'.tr,
                  active: false,
                  onTap: () {
                    Navigator.pop(context);
                    showJamSheet(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
