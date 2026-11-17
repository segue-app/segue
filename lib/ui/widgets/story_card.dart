import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/track.dart';
import '../../core/player/player.dart';
import '../../core/share/track_link.dart';
import '../../core/sources/match_source.dart';
import '../../core/sources/sources.dart';
import '../theme/artwork_colors.dart';
import '../theme/theme.dart';
import 'artwork.dart';

import 'package:segue/core/l10n/l10n.dart';

/// "Карточка для сторис": a 1080 × 1920 picture of the song (cover, title,
/// a line of its lyrics if you like, and a code that opens it) to post in
/// Instagram or Telegram stories. Shown first, then shared or saved.
Future<void> showStoryCard(BuildContext context, Track track) => showDialog(
  context: context,
  useRootNavigator: true,
  builder: (_) => _StoryDialog(track: track),
);

/// Card size in logical pixels; rendered at 3× for 1080 × 1920.
const _w = 360.0, _h = 640.0, _scale = 3.0;

class _StoryDialog extends ConsumerStatefulWidget {
  const _StoryDialog({required this.track});

  final Track track;

  @override
  ConsumerState<_StoryDialog> createState() => _StoryDialogState();
}

class _StoryDialogState extends ConsumerState<_StoryDialog> {
  final _card = GlobalKey();
  final _shareButton = GlobalKey();

  /// Index of the lyric line on the card; -1 for none.
  int _line = -1;
  bool _picked = false;
  bool _busy = false;

  Track get track => widget.track;

  String get _link {
    final match = ref.read(sourcesProvider)[SourceKind.match];
    final youtubeId = track.source == SourceKind.match && match is MatchSource
        ? match.matched(track)?.id
        : null;
    return TrackLink.webLink(track, youtubeId: youtubeId);
  }

  /// Lines worth putting on a card: words, not empty or "♪" breaks.
  static List<String> _lines(Lyrics? l) => [
    for (final line in l?.lines ?? const <LyricLine>[])
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(line.text))
        line.text.trim(),
  ];

  /// The line being sung now, if this song is playing.
  int _nowLine(Lyrics l, List<String> lines) {
    final player = ref.read(playerProvider);
    if (player.current?.key != track.key || !l.synced) return -1;
    final pos = ref.read(positionProvider).value ?? Duration.zero;
    final i = l.lineAt(pos - l.shift);
    if (i < 0) return -1;
    return lines.indexOf(l.lines[i].text.trim());
  }

  Future<Uint8List> _png() async {
    final boundary =
        _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _scale);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  String get _fileName {
    final safe = '${track.artist} — ${track.displayTitle}'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .trim();
    return 'Segue — $safe.png';
  }

  static bool get _canShare =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> _share() => _run(() async {
    final bytes = await _png();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/stories/$_fileName');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    final box = _shareButton.currentContext?.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  });

  Future<void> _save() => _run(() async {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Сохранить карточку'.tr,
      fileName: _fileName,
      bytes: await _png(),
      mimeType: 'image/png',
    );
    if (saved != null && mounted) _say('Карточка сохранена'.tr);
  });

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) _say('Не получилось: {0}'.trArgs([e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(lyricsProvider(track)).value;
    final lines = _lines(lyrics);
    if (!_picked && lyrics != null) {
      // Start on the line playing now; the user can change or drop it.
      _picked = true;
      _line = _nowLine(lyrics, lines);
    }
    if (_line >= lines.length) _line = -1;
    final url = track.artworkUrl;
    final colors = url == null
        ? ArtworkColors.fallback
        : ref.watch(colorsForUrlProvider(url)).value ?? ArtworkColors.fallback;

    final card = RepaintBoundary(
      key: _card,
      child: StoryCard(
        track: track,
        colors: colors,
        line: _line < 0 ? null : lines[_line],
        link: _link,
      ),
    );

    return Dialog(
      backgroundColor: SegueColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Карточка для сторис'.tr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: AspectRatio(
                  aspectRatio: _w / _h,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FittedBox(
                      child: SizedBox(width: _w, height: _h, child: card),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (lines.isNotEmpty)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Предыдущая строчка'.tr,
                      onPressed: () => setState(
                        () => _line = _line <= 0 ? lines.length - 1 : _line - 1,
                      ),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _line < 0
                            ? 'Без строчки из песни'.tr
                            : 'Строчка {0} из {1}'.trArgs([
                                _line + 1,
                                lines.length,
                              ]),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SegueColors.textDim),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Следующая строчка'.tr,
                      onPressed: () => setState(
                        () =>
                            _line = _line + 1 >= lines.length ? -1 : _line + 1,
                      ),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    if (_line >= 0)
                      IconButton(
                        tooltip: 'Убрать строчку'.tr,
                        onPressed: () => setState(() => _line = -1),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.download_rounded),
                      label: Text('Сохранить'.tr),
                    ),
                  ),
                  if (_canShare) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: _shareButton,
                        onPressed: _busy ? null : _share,
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text('Поделиться'.tr),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card itself, 360 × 640 logical pixels.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.track,
    required this.colors,
    required this.link,
    this.line,
  });

  final Track track;
  final ArtworkColors colors;
  final String link;
  final String? line;

  /// A cover big enough for a 1080-wide picture.
  static String? _bigCover(String? url) {
    if (url == null || !url.contains('dzcdn.net')) return url;
    return url.replaceFirst(RegExp(r'/\d+x\d+-'), '/1000x1000-');
  }

  @override
  Widget build(BuildContext context) {
    final cover = _bigCover(track.artworkUrl);
    final glow = colors.palette.isNotEmpty
        ? colors.palette.first
        : colors.accent;
    final second = colors.palette.length > 1 ? colors.palette[1] : glow;
    final base = Color.lerp(colors.background, Colors.black, 0.35)!;
    final hasLine = line != null;
    final coverSize = hasLine ? 232.0 : 276.0;

    return MediaQuery(
      // The preview may be scaled down; the card is drawn at its own size.
      data: MediaQuery.of(context)
          .copyWith(devicePixelRatio: _scale, textScaler: TextScaler.noScaling),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(color: Colors.white),
        child: Container(
          width: _w,
          height: _h,
          color: base,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The cover, blurred into a wash of its own colours.
              if (cover != null)
                Opacity(
                  opacity: 0.55,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 46,
                      sigmaY: 46,
                      tileMode: TileMode.decal,
                    ),
                    child: Transform.scale(
                      scale: 1.6,
                      child: Image(
                        image: coverProvider(cover),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.7, -0.75),
                    radius: 1.1,
                    colors: [glow.withValues(alpha: 0.55), Colors.transparent],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.9, 0.55),
                    radius: 1.0,
                    colors: [second.withValues(alpha: 0.4), Colors.transparent],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.55, 1],
                    colors: [
                      Colors.transparent,
                      base.withValues(alpha: 0.25),
                      base.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 3),
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 36,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Artwork(url: cover, size: coverSize, radius: 18),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      track.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 27,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    if (hasLine) ...[
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: colors.accent, width: 3),
                          ),
                        ),
                        child: Text(
                          line!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(flex: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Image.asset(
                          'assets/brand/mark_256.png',
                          width: 30,
                          height: 30,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Segue',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: QrImageView(
                                data: link,
                                size: 62,
                                padding: EdgeInsets.zero,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.circle,
                                  color: Color(0xFF111114),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.circle,
                                  color: Color(0xFF111114),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Слушать'.tr,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
