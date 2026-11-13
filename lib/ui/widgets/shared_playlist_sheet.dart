import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/l10n.dart';
import '../../core/library/library.dart';
import '../../core/sync/shared_playlists.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';

/// "Совместный плейлист": share this playlist with friends, or stop.
Future<void> showSharedPlaylistSheet(BuildContext context, String playlistId) =>
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
      builder: (_) => _SharedSheet(playlistId),
    );

class _SharedSheet extends ConsumerStatefulWidget {
  const _SharedSheet(this.playlistId);
  final String playlistId;

  @override
  ConsumerState<_SharedSheet> createState() => _SharedSheetState();
}

class _SharedSheetState extends ConsumerState<_SharedSheet> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final shared = ref.read(sharedPlaylistsProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    final name =
        ref
            .watch(playlistsProvider)
            .where((p) => p.id == widget.playlistId)
            .firstOrNull
            ?.name ??
        '';
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: shared.codes,
      builder: (context, codes, _) {
        final code = codes[widget.playlistId];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Совместный плейлист'.tr,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Друзья с кодом добавляют, убирают и переставляют песни: у всех один и тот же список, в любой сети.'
                      .tr,
                  style: const TextStyle(color: SegueColors.textDim),
                ),
                const SizedBox(height: 18),
                if (code == null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: SegueColors.ink,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() {
                                _busy = true;
                                _error = null;
                              });
                              try {
                                await shared.share(widget.playlistId);
                              } catch (e) {
                                _error = '$e'.replaceFirst('Bad state: ', '');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.group_add_rounded),
                      label: Text(
                        _busy ? '…' : 'Сделать совместным'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: 'segue://playlist?c=$code',
                          size: 120,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${code.substring(0, 4)}-${code.substring(4)}',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: SharedPlaylists.invite(name, code),
                                  ),
                                );
                                ScaffoldMessenger.maybeOf(
                                  context,
                                )?.showSnackBar(
                                  SnackBar(
                                    content: Text('Приглашение скопировано'.tr),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.link_rounded),
                              label: Text('Копировать приглашение'.tr),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        shared.stopSharing(widget.playlistId);
                        Navigator.pop(context);
                      },
                      child: Text('Перестать участвовать'.tr),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF6B81)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Присоединиться по коду": a friend's shared playlist. Returns its id.
Future<String?> askJoinSharedPlaylist(BuildContext context, WidgetRef ref) =>
    showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => _JoinDialog(ref.read(sharedPlaylistsProvider)),
    );

class _JoinDialog extends StatefulWidget {
  const _JoinDialog(this.shared);
  final SharedPlaylists shared;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.shared.join(_code.text);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      setState(
        () => _error = '$e'
            .replaceFirst('Bad state: ', '')
            .replaceFirst('FormatException: ', ''),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: SegueColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    title: Text('Плейлист друга'.tr),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Введи код из приглашения'.tr,
          style: const TextStyle(color: SegueColors.textDim),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'ABCD-EFGH'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
            LengthLimitingTextInputFormatter(9),
          ],
          onSubmitted: (_) => _join(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Отмена'.tr),
      ),
      FilledButton(
        onPressed: _busy ? null : _join,
        child: Text(_busy ? '…' : 'Войти'.tr),
      ),
    ],
  );
}
