import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A horizontal row (releases, artists, chips) that a mouse can move too:
/// ‹ › buttons appear on hover, the row can be dragged, and the wheel
/// scrolls it with Shift. Touch and trackpads work as before.
///
/// [builder] gets the controller to give its horizontal list.
class HScroll extends StatefulWidget {
  const HScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<HScroll> createState() => _HScrollState();
}

class _HScrollState extends State<HScroll> {
  final _c = ScrollController();
  bool _hover = false, _back = false, _forward = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _update() {
    if (!_c.hasClients) return;
    final p = _c.position;
    final back = p.pixels > p.minScrollExtent + 1;
    final forward = p.pixels < p.maxScrollExtent - 1;
    if (back != _back || forward != _forward) {
      setState(() {
        _back = back;
        _forward = forward;
      });
    }
  }

  void _page(int dir) {
    if (!_c.hasClients) return;
    final p = _c.position;
    _c.animateTo(
      (p.pixels + dir * p.viewportDimension * 0.8).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        _update();
      },
      onExit: (_) => setState(() => _hover = false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _update();
          });
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _update();
            return false;
          },
          child: LayoutBuilder(
            builder: (context, box) {
              final size = math
                  .min(40.0, box.maxHeight.isFinite ? box.maxHeight - 4 : 40.0)
                  .clamp(24.0, 40.0);
              return Stack(
                children: [
                  ScrollConfiguration(
                    // A mouse can drag the row like a finger.
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                    child: widget.builder(context, _c),
                  ),
                  _arrow(left: true, size: size, show: _hover && _back),
                  _arrow(left: false, size: size, show: _hover && _forward),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _arrow({
    required bool left,
    required double size,
    required bool show,
  }) => Positioned(
    left: left ? 6 : null,
    right: left ? null : 6,
    top: 0,
    bottom: 0,
    child: Center(
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Material(
            color: SegueColors.surface.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              key: ValueKey(left ? 'hscroll-back' : 'hscroll-forward'),
              customBorder: const CircleBorder(),
              onTap: () => _page(left ? -1 : 1),
              child: SizedBox.square(
                dimension: size,
                child: Icon(
                  left
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: size * 0.7,
                  color: SegueColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
