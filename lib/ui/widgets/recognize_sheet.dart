import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog/wave.dart';
import '../../core/library/library.dart';
import '../../core/player/player.dart';
import '../../core/recognize/shazam.dart';
import '../../core/recognize/song_listener.dart';
import '../theme/theme.dart';
import 'artwork.dart';
import 'segue_loader.dart';
import 'track_actions.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Что играет?": listens, names the song, offers to play it. Below,
/// what was recognised before.
Future<void> showRecognizeSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: SegueColors.surface,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 520),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => const _RecognizeSheet(),
);

enum _Stage { listening, found, unknown, failed }

class _RecognizeSheet extends ConsumerStatefulWidget {
  const _RecognizeSheet();

  @override
  ConsumerState<_RecognizeSheet> createState() => _RecognizeSheetState();
}

class _RecognizeSheetState extends ConsumerState<_RecognizeSheet> {
  _Stage _stage = _Stage.listening;
  double _heard = 0;

  /// Recent loudness, oldest first: the bars while listening.
  final _levels = List<double>.filled(_LevelBars.count, 0);
  RecognizedSong? _song;
  String? _error;
  bool _permission = false;

  /// Microphone or this device's own sound; the last choice is kept.
  ListenSource _source = ListenSource.microphone;
  bool _deviceOk = false;

  /// Which listening run is current: a switch of source starts a new one,
  /// and the old one's answer is ignored.
  int _run = 0;

  /// Segue's own music was paused to hear the room; it comes back after.
  bool _paused = false;

  late final SongListener _listener = ref.read(songListenerProvider);
  // Kept from the start: the sheet resumes the music while closing, when
  // reading providers is no longer allowed.
  late final _player = ref.read(playerProvider);

  static const _sourceKey = 'recognize_source';

  @override
  void initState() {
    super.initState();
    _player; // read now, while it's allowed
    final library = ref.read(libraryProvider);
    unawaited(() async {
      _deviceOk = await SongListener.deviceSupported();
      if (_deviceOk && library.getMeta(_sourceKey) == 'device') {
        _source = ListenSource.device;
      }
      if (mounted) unawaited(_listen());
    }());
  }

  Future<void> _switch(ListenSource source) async {
    if (source == _source) return;
    ref.read(libraryProvider).setMeta(_sourceKey, source.name);
    setState(() => _source = source);
    await _listener.cancel();
    if (mounted) await _listen();
  }

  @override
  void dispose() {
    unawaited(_listener.cancel());
    _resume();
    super.dispose();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    unawaited(_player.play());
  }

  Future<void> _listen() async {
    final run = ++_run;
    setState(() {
      _stage = _Stage.listening;
      _heard = 0;
      _levels.fillRange(0, _levels.length, 0);
      _error = null;
      _permission = false;
    });
    // The room is heard through the microphone: Segue's own music would
    // drown it. This device's sound leaves Segue out by itself.
    if (_source == ListenSource.microphone &&
        _player.playbackState.value.playing) {
      _paused = true;
      await _player.pause();
    } else if (_source == ListenSource.device) {
      _resume();
    }
    try {
      final song = await _listener.listen(
        source: _source,
        heard: (s) {
          if (mounted && run == _run) setState(() => _heard = s);
        },
        level: (l) {
          if (run != _run) return;
          _levels
            ..removeAt(0)
            ..add(l);
        },
      );
      if (!mounted || run != _run) return;
      if (song != null) _listener.remember(song);
      setState(() {
        _song = song;
        _stage = song == null ? _Stage.unknown : _Stage.found;
      });
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _stage = _Stage.failed;
        _error = '$e';
        _permission = e is ListenException && e.permission;
      });
    } finally {
      // Something was named, or nothing will be: the music goes on (unless
      // the user plays what was found, which starts it anyway).
      if (mounted && run == _run && _stage != _Stage.listening) _resume();
    }
  }

  void _play(RecognizedSong song) {
    _paused = false;
    ref.read(playerProvider).playList([song.track], 0, context: 'recognized');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final history = _listener.history();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_deviceOk) ...[
                SegmentedButton<ListenSource>(
                  segments: [
                    ButtonSegment(
                      value: ListenSource.microphone,
                      icon: const Icon(Icons.mic_rounded),
                      label: Text('Вокруг'.tr),
                    ),
                    ButtonSegment(
                      value: ListenSource.device,
                      icon: const Icon(Icons.laptop_mac_rounded),
                      label: Text('На этом Mac'.tr),
                    ),
                  ],
                  selected: {_source},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _switch(v.first),
                ),
                const SizedBox(height: 8),
              ],
              AnimatedSwitcher(
                duration: SegueMotion.medium,
                child: KeyedSubtree(
                  key: ValueKey(_stage),
                  child: switch (_stage) {
                    _Stage.listening => _listening(),
                    _Stage.found => _found(_song!),
                    _Stage.unknown => _message(
                      Icons.hearing_disabled_rounded,
                      'Не узнал песню'.tr,
                      'Поднеси устройство ближе к звуку и попробуй ещё раз'.tr,
                    ),
                    _Stage.failed => _message(
                      _permission
                          ? Icons.mic_off_rounded
                          : Icons.cloud_off_rounded,
                      'Не получилось'.tr,
                      _error ?? '',
                    ),
                  },
                ),
              ),
              if (_stage != _Stage.listening) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _listen,
                  icon: const Icon(Icons.mic_rounded),
                  label: Text('Слушать ещё раз'.tr),
                ),
              ],
              if (history.isNotEmpty && _stage != _Stage.listening) ...[
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Узнанные раньше'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final e in history.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Artwork(url: e.song.coverUrl, size: 44, radius: 8),
                    title: Text(
                      e.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${e.song.artist} · ${_when(e.at)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: SegueColors.textDim),
                    ),
                    onTap: () => _play(e.song),
                    onLongPress: () =>
                        showTrackActions(context, ref, e.song.track),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'только что'.tr;
    if (d.inHours < 1) return '{0} мин назад'.trArgs([d.inMinutes]);
    if (d.inDays < 1) return '{0} ч назад'.trArgs([d.inHours]);
    return '${at.day.toString().padLeft(2, '0')}.'
        '${at.month.toString().padLeft(2, '0')}.${at.year}';
  }

  Widget _listening() {
    final total = SongListener.tries.last.toDouble();
    return Column(
      children: [
        const SizedBox(height: 18),
        const SegueLoader(size: 84),
        const SizedBox(height: 22),
        Text(
          // The microphone takes a few seconds to start on some Macs.
          _heard == 0 ? 'Подключаюсь…'.tr : 'Слушаю…'.tr,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _source == ListenSource.device
              ? 'Включи песню в любом приложении на этом устройстве'.tr
              : 'Поднеси устройство к источнику звука'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(color: SegueColors.textDim),
        ),
        const SizedBox(height: 18),
        _LevelBars(
          levels: _levels,
          progress: (_heard / total).clamp(0.0, 1.0),
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Отмена'.tr),
        ),
      ],
    );
  }

  Widget _found(RecognizedSong song) {
    final library = ref.read(libraryProvider);
    final track = song.track;
    final liked = library.isLiked(track);
    return Column(
      children: [
        const SizedBox(height: 6),
        Artwork(url: song.coverUrl, size: 200, radius: 18),
        const SizedBox(height: 18),
        Text(
          song.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          song.artist,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: SegueColors.textDim),
        ),
        if (song.album != null || song.year != null) ...[
          const SizedBox(height: 4),
          Text(
            [song.album, song.year].whereType<String>().join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: SegueColors.textDim),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => _play(song),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Играть'.tr),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => library.setLiked(track, !liked)),
              icon: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              ),
              label: Text(liked ? 'В любимых'.tr : 'В любимые'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _paused = false;
                final messenger = ScaffoldMessenger.maybeOf(context);
                ref.read(waveProvider).trackWave(track).catchError((Object e) {
                  messenger?.showSnackBar(
                    SnackBar(content: Text('Не получилось запустить волну'.tr)),
                  );
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.waves_rounded),
              label: Text('Волна по треку'.tr),
            ),
          ],
        ),
      ],
    );
  }

  Widget _message(IconData icon, String title, String text) => Column(
    children: [
      const SizedBox(height: 18),
      Icon(icon, size: 56, color: SegueColors.textDim),
      const SizedBox(height: 14),
      Text(
        title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: SegueColors.textDim, height: 1.4),
      ),
    ],
  );
}

/// What the microphone hears, as bars that jump with the sound: the
/// newest on the right. The part already heard is lit, the rest waits dim,
/// so the bars are also the progress.
class _LevelBars extends StatelessWidget {
  const _LevelBars({
    required this.levels,
    required this.progress,
    required this.color,
  });

  static const count = 36;

  final List<double> levels;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarsPainter(List.of(levels), progress, color),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.levels, this.progress, this.color);

  final List<double> levels;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = levels.length;
    final gap = size.width / n;
    final w = gap * 0.55;
    final lit = (progress * n).round();
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      // A little of the neighbours: one loud piece doesn't make a spike.
      final a = levels[i];
      final b = i > 0 ? levels[i - 1] : a;
      final c = i < n - 1 ? levels[i + 1] : a;
      final v = (a * 0.6 + (b + c) * 0.2).clamp(0.0, 1.0);
      final h = 4 + v * (size.height - 4);
      final x = i * gap + (gap - w) / 2;
      final paint = Paint()
        ..color = i < lit ? color : color.withValues(alpha: 0.22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - h / 2, w, h),
          Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}
