import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/sources/match_source.dart';
import '../../core/sources/sources.dart';
import '../theme/theme.dart';
import 'artwork.dart';

/// An imported song plays a YouTube version found automatically; here the
/// user sees the versions found and picks the right one.
Future<void> showMatchSheet(BuildContext context, Track track) =>
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
      builder: (_) => _MatchSheet(track),
    );

class _MatchSheet extends ConsumerStatefulWidget {
  const _MatchSheet(this.track);
  final Track track;

  @override
  ConsumerState<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends ConsumerState<_MatchSheet> {
  late final MatchSource _match =
      ref.read(sourcesProvider)[SourceKind.match]! as MatchSource;
  late final Future<List<MatchCandidate>> _found = _match.candidates(
    widget.track,
  );

  String _len(Duration? d) {
    if (d == null) return '';
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _pick(Track t) async {
    _match.choose(widget.track, t);
    Navigator.pop(context);
    await ref.read(playerProvider).reloadTrack(widget.track);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _match.matched(widget.track)?.id;
    final want = widget.track.duration;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Выбери версию',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.track.artist} — ${widget.track.title}'
                    '${want == null ? '' : ' · ${_len(want)}'}',
                    style: const TextStyle(color: SegueColors.textDim),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<MatchCandidate>>(
                future: _found,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(child: Text('Не удалось найти версии'));
                  }
                  final list = snap.data;
                  if (list == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (list.isEmpty) {
                    return const Center(child: Text('Ничего не нашлось'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      final t = c.track;
                      final on = t.id == chosen;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selected: on,
                        leading: Artwork(
                          url: t.artworkUrl,
                          size: 48,
                          radius: 10,
                        ),
                        title: Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            t.artist,
                            _len(t.duration),
                            if (c.official) 'официальный канал',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(color: SegueColors.textDim),
                        ),
                        trailing: on ? const Icon(Icons.check_rounded) : null,
                        onTap: () => _pick(t),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
