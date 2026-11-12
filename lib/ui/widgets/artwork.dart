import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'disk_image.dart';

/// Rounded cover art that fades in softly once loaded.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 12,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: SegueColors.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: SegueColors.textDim.withValues(alpha: 0.6),
        size: size * 0.38,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? placeholder
            : Stack(
                fit: StackFit.expand,
                children: [
                  placeholder,
                  // Local covers (own music folders) are files, not URLs.
                  if (isLocalImage(url!))
                    Image.file(
                      File(url!),
                      fit: BoxFit.cover,
                      cacheWidth:
                          (size * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      errorBuilder: (_, _, _) => const SizedBox(),
                    )
                  else
                    Image(
                      // Decoded at display size (lists stay smooth) and
                      // kept on disk (no download on the next launch).
                      image: ResizeImage(
                        DiskImage(
                          coverUrlFor(
                            url!,
                            size * MediaQuery.devicePixelRatioOf(context),
                          ),
                        ),
                        width: (size * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                      ),
                      fit: BoxFit.cover,
                      // Older YouTube videos have no hq720 thumbnail.
                      errorBuilder: (_, _, _) => url!.contains('/hq720.jpg')
                          ? Image(
                              image: ResizeImage(
                                DiskImage(
                                  url!.replaceFirst(
                                    '/hq720.jpg',
                                    '/mqdefault.jpg',
                                  ),
                                ),
                                width:
                                    (size *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .round(),
                              ),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            )
                          : const SizedBox(),
                      frameBuilder: (_, child, frame, sync) => sync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: SegueMotion.medium,
                              curve: SegueMotion.ease,
                              child: child,
                            ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// The smallest version of a cover that still looks sharp at [pixels]
/// across: a 48-point row doesn't need a 1000×1000 download.
String coverUrlFor(String url, double pixels) {
  // Deezer's CDN makes any size on request.
  final deezer = RegExp(r'/(\d+)x(\d+)-').firstMatch(url);
  if (deezer != null && url.contains('dzcdn.net')) {
    final want = pixels <= 140
        ? 140
        : pixels <= 264
        ? 264
        : pixels <= 500
        ? 500
        : 1000;
    final have = int.tryParse(deezer.group(1)!) ?? 1000;
    if (want < have) {
      return url.replaceFirst(deezer.group(0)!, '/${want}x$want-');
    }
    return url;
  }
  // YouTube: the 320×180 thumbnail exists for every video.
  if (pixels <= 200 &&
      url.contains('i.ytimg.com') &&
      url.endsWith('/hq720.jpg')) {
    return url.replaceFirst('/hq720.jpg', '/mqdefault.jpg');
  }
  return url;
}

String formatDuration(Duration? d) {
  if (d == null) return '';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

bool isLocalImage(String url) =>
    url.startsWith('/') ||
    url.startsWith('file://') ||
    RegExp(r'^[A-Za-z]:\\').hasMatch(url);

/// ImageProvider for a cover URL or a local cover file.
ImageProvider coverProvider(String url) => isLocalImage(url)
    ? FileImage(File(url.replaceFirst('file://', '')))
    : DiskImage(url) as ImageProvider;
