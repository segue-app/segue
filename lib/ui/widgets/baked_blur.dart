import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'artwork.dart';
import 'disk_image.dart';

/// A cover blurred into a soft wash of its colours, as a background.
///
/// Blurred once per song on a small copy (a few dozen pixels), then only
/// stretched: a live full-screen blur was recomputed every frame the
/// player changed, which slow phones and laptop graphics can't keep up.
class BakedBlur extends StatefulWidget {
  const BakedBlur({super.key, required this.url, this.zoom = 1.6});

  final String? url;

  /// How much the cover is enlarged inside the wash (its edges stay out).
  final double zoom;

  @override
  State<BakedBlur> createState() => _BakedBlurState();
}

class _BakedBlurState extends State<BakedBlur> {
  static const _px = 72;
  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BakedBlur old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final job = ++_job;
    _stop();
    final url = widget.url;
    if (url == null) return;
    final ImageProvider base = isLocalImage(url)
        ? FileImage(File(url))
        : DiskImage(coverUrlFor(url, 120));
    final stream = ResizeImage(
      base,
      width: _px,
      height: _px,
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      _bake(info.image, job);
    }, onError: (_, _) {});
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  Future<void> _bake(ui.Image src, int job) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const s = _px * 1.0;
    final zoomed = Rect.fromCenter(
      center: const Offset(s / 2, s / 2),
      width: s * widget.zoom,
      height: s * widget.zoom,
    );
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      zoomed,
      Paint()
        ..filterQuality = FilterQuality.medium
        // ~110 at full-screen size, scaled down to this copy.
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 8,
          sigmaY: 8,
          tileMode: TileMode.clamp,
        ),
    );
    final out = await rec.endRecording().toImage(_px, _px);
    if (!mounted || job != _job) {
      out.dispose();
      return;
    }
    final old = _image;
    setState(() => _image = out);
    // The old one fades out first: freed once it's gone from the screen.
    if (old != null) {
      Future<void>.delayed(const Duration(seconds: 1), old.dispose);
    }
  }

  void _stop() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: img == null
          ? const SizedBox.expand(key: ValueKey('none'))
          : RawImage(
              key: ValueKey(img),
              image: img,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              // Smooth stretching is what makes the wash.
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
