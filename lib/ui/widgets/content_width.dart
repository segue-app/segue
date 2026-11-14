import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How wide the readable content of a screen may be. Scrolling views under
/// it span the whole width (the wheel, a drag and the scrollbar work
/// anywhere, the scrollbar sits at the window's edge) and pad their
/// content into the middle instead of being narrowed themselves.
class ContentWidth extends InheritedWidget {
  const ContentWidth({super.key, required this.max, required super.child});

  final double max;

  static double maxOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentWidth>()?.max ??
      double.infinity;

  /// Room on each side for content at most [max] wide in [width].
  static double sideFor(double width, double max) =>
      max.isFinite ? math.max(0.0, (width - max) / 2) : 0.0;

  @override
  bool updateShouldNotify(ContentWidth old) => old.max != max;
}

/// A scroll view across the whole width with its content in the middle:
/// [builder] gets the extra padding for each side.
class WideScroll extends StatelessWidget {
  const WideScroll({super.key, required this.builder, this.max});

  final Widget Function(BuildContext context, double side) builder;

  /// Defaults to the surrounding [ContentWidth].
  final double? max;

  @override
  Widget build(BuildContext context) {
    final m = max ?? ContentWidth.maxOf(context);
    return LayoutBuilder(
      builder: (context, box) =>
          builder(context, ContentWidth.sideFor(box.maxWidth, m)),
    );
  }
}

/// A part that doesn't scroll (a title, tabs), kept at the content width
/// in the middle.
class ContentBox extends StatelessWidget {
  const ContentBox({super.key, required this.child, this.max});

  final Widget child;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final m = max ?? ContentWidth.maxOf(context);
    if (!m.isFinite) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: m),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
