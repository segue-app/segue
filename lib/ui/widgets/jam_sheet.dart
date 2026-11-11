import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/sync/jam.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'motion.dart';

/// "Слушать вместе": start a session, join one, see who listens and what's
/// next.
Future<void> showJamSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 560),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => const _JamSheet(),
);

String jamLink(String code) => 'segue://jam?c=$code';

class _JamSheet extends ConsumerStatefulWidget {
  const _JamSheet();

  @override
  ConsumerState<_JamSheet> createState() => _JamSheetState();
}

class _JamSheetState extends ConsumerState<_JamSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      _error = '$e'.replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jam = ref.read(jamProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: Listenable.merge([
        jam.code,
        jam.members,
        jam.upcoming,
        jam.hostName,
      ]),
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: AnimatedSize(
            duration: SegueMotion.medium,
            alignment: Alignment.topCenter,
            child: !jam.active
                ? _start(jam, accent)
                : jam.isHost.value
                ? _hosting(jam, accent)
                : _guest(jam, accent),
          ),
        ),
      ),
    );
  }

  Widget _title(String text, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(color: SegueColors.textDim)),
      const SizedBox(height: 18),
    ],
  );

  Widget _start(JamService jam, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Слушать вместе',
        'Друзья слышат то же, что и ты, в ту же секунду — каждый на своём '
            'устройстве, в любой сети. Добавлять песни в очередь могут все.',
      ),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: SegueColors.ink,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _busy ? null : () => _run(() => jam.host()),
          icon: const Icon(Icons.group_add_rounded),
          label: const Text(
            'Начать и позвать друзей',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        'Есть код от друга?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'ABCD-EFGH'),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(9),
              ],
              onSubmitted: (v) => _run(() => jam.join(v)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => jam.join(_code.text)),
            child: Text(_busy ? '…' : 'Войти'),
          ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: const TextStyle(color: Color(0xFFFF6B81))),
      ],
    ],
  );

  Widget _hosting(JamService jam, Color accent) {
    final code = jam.code.value!;
    final pretty = '${code.substring(0, 4)}-${code.substring(4)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Слушаем вместе', 'Отправь друзьям ссылку или код'),
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
                data: jamLink(code),
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
                    pretty,
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
                          text:
                              'Послушай со мной в Segue: ${jamLink(code)} '
                              '(или код $pretty)',
                        ),
                      );
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Приглашение скопировано'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Копировать приглашение'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _members(jam, accent),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: jam.leave,
            child: const Text('Завершить для всех'),
          ),
        ),
      ],
    );
  }

  Widget _guest(JamService jam, Color accent) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Слушаешь с ${jam.hostName.value}',
        'Музыку ведёт ${jam.hostName.value}. Песни можно добавлять через '
            'меню трека → «В совместную очередь»',
      ),
      _members(jam, accent),
      if (jam.upcoming.value.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Дальше', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final t in jam.upcoming.value.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Artwork(url: t.artworkUrl, size: 40, radius: 10),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              t.artist,
              style: const TextStyle(color: SegueColors.textDim),
            ),
          ),
      ],
      const SizedBox(height: 12),
      Center(
        child: TextButton(onPressed: jam.leave, child: const Text('Выйти')),
      ),
    ],
  );

  Widget _members(JamService jam, Color accent) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in jam.members.value)
          Chip(
            avatar: CircleAvatar(
              backgroundColor: m.host ? accent : Colors.white24,
              child: Text(
                m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  color: m.host ? SegueColors.ink : Colors.white,
                ),
              ),
            ),
            label: Text(m.host ? '${m.name} · ведёт' : m.name),
          ),
      ],
    ),
  );
}

/// "Слушаем вместе · 3" above the player while in a session.
class JamBar extends ConsumerWidget {
  const JamBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jam = ref.read(jamProvider);
    final accent = ref.watch(currentColorsProvider).accent;
    return ListenableBuilder(
      listenable: Listenable.merge([jam.code, jam.members, jam.hostName]),
      builder: (context, _) => AnimatedSwitcher(
        duration: SegueMotion.slow,
        transitionBuilder: (c, a) => SizeTransition(
          sizeFactor: a,
          child: FadeTransition(opacity: a, child: c),
        ),
        child: !jam.active
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: const ValueKey('jam'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: PressScale(
                  scale: 0.98,
                  onTap: () => showJamSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.28),
                          const Color(0xFF7B5CFF).withValues(alpha: 0.22),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.groups_rounded, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            jam.isHost.value
                                ? 'Слушаем вместе · ${jam.members.value.length}'
                                : 'Слушаешь с ${jam.hostName.value} · '
                                      '${jam.members.value.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
