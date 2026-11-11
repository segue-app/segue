import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/player/trims.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';

/// "Обрезать трек": pick where the track starts and stops. Saved on this
/// device and applied every time it plays.
Future<void> showTrimSheet(BuildContext context, Track track) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: SegueColors.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 620),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _TrimSheet(track: track),
    );

class _TrimSheet extends ConsumerStatefulWidget {
  const _TrimSheet({required this.track});
  final Track track;

  @override
  ConsumerState<_TrimSheet> createState() => _TrimSheetState();
}

class _TrimSheetState extends ConsumerState<_TrimSheet> {
  late RangeValues _range;
  late final Duration? _total;

  bool get _isCurrent =>
      ref.read(playerProvider).current?.key == widget.track.key;

  @override
  void initState() {
    super.initState();
    // The player knows the exact length of what is playing.
    _total = _isCurrent
        ? ref.read(durationProvider).value ?? widget.track.duration
        : widget.track.duration;
    final saved = ref.read(trimStoreProvider).of(widget.track);
    final max = (_total?.inMilliseconds ?? 0) / 1000;
    _range = RangeValues(
      ((saved?.start?.inMilliseconds ?? 0) / 1000).clamp(0, max),
      ((saved?.end?.inMilliseconds ?? (max * 1000).round()) / 1000).clamp(
        0,
        max,
      ),
    );
  }

  static String _fmt(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  void _listen(double at) {
    final player = ref.read(playerProvider);
    if (!_isCurrent) return;
    player.seek(Duration(milliseconds: (at * 1000).round()));
    player.play();
  }

  void _save({bool reset = false}) {
    final total = _total;
    if (total == null) return;
    final max = total.inMilliseconds / 1000;
    ref
        .read(trimStoreProvider)
        .set(
          widget.track,
          reset
              ? null
              : Trim(
                  // Untouched ends stay open: no trim on that side.
                  start: _range.start < 0.5
                      ? null
                      : Duration(milliseconds: (_range.start * 1000).round()),
                  end: _range.end > max - 0.5
                      ? null
                      : Duration(milliseconds: (_range.end * 1000).round()),
                ),
        );
    if (_isCurrent) ref.read(playerProvider).refreshTrim();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(currentColorsProvider).accent;
    final total = _total;
    final t = widget.track;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Обрезать трек',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Трек всегда будет играть только выбранный кусок',
              style: TextStyle(color: SegueColors.textDim, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Artwork(url: t.artworkUrl, size: 48, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: SegueColors.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (total == null || total.inSeconds < 5)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Длина трека пока неизвестна. Включи его, и можно будет '
                  'обрезать.',
                  style: TextStyle(color: SegueColors.textDim),
                ),
              )
            else ...[
              Row(
                children: [
                  _Time('Начало', _fmt(_range.start)),
                  const Spacer(),
                  Text(
                    'будет ${_fmt(_range.end - _range.start)}',
                    style: const TextStyle(color: SegueColors.textDim),
                  ),
                  const Spacer(),
                  _Time('Конец', _fmt(_range.end), end: true),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: accent,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
                  thumbColor: Colors.white,
                  overlayColor: accent.withValues(alpha: 0.15),
                ),
                child: RangeSlider(
                  values: _range,
                  max: total.inMilliseconds / 1000,
                  // At least five seconds of music must remain.
                  onChanged: (v) {
                    if (v.end - v.start >= 5) setState(() => _range = v);
                  },
                  onChangeEnd: (v) {
                    // Hear where you dropped the handle (current track only).
                    if (v.start != _range.start) return;
                    _listen(v.start);
                  },
                ),
              ),
              if (_isCurrent)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _listen(_range.start),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Послушать начало'),
                    ),
                    TextButton.icon(
                      onPressed: () => _listen(
                        (_range.end - 5).clamp(_range.start, _range.end),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Послушать конец'),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _save(reset: true),
                    child: const Text('Без обрезки'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: SegueColors.ink,
                    ),
                    onPressed: _save,
                    child: const Text(
                      'Сохранить',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time(this.label, this.value, {this.end = false});
  final String label;
  final String value;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: SegueColors.textDim, fontSize: 12),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
