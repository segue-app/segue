import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Shrinks slightly while pressed and springs back: makes taps feel physical.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.94,
    this.onWarm,
    this.hoverRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Called when a tap looks likely: the pointer rests on the widget or a
  /// finger touches it. Used to get a track ready before it is tapped.
  final VoidCallback? onWarm;

  /// Set to light the widget up softly under the mouse pointer.
  final double? hoverRadius;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  bool _hover = false;
  Timer? _rest;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  void _hovered(bool v) {
    _rest?.cancel();
    if (v && widget.onWarm != null) {
      // Only when the pointer stays: passing over a list warms nothing.
      _rest = Timer(const Duration(milliseconds: 140), widget.onWarm!);
    }
    if (widget.hoverRadius != null && _hover != v) setState(() => _hover = v);
  }

  @override
  void dispose() {
    _rest?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (widget.hoverRadius != null) {
      child = AnimatedContainer(
        duration: SegueMotion.fast,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _hover ? 0.055 : 0),
          borderRadius: BorderRadius.circular(widget.hoverRadius!),
        ),
        child: child,
      );
    }
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => _hovered(true),
      onExit: (_) => _hovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _set(true);
          widget.onWarm?.call();
        },
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        // Right click on desktop opens the same menu as a long press.
        onSecondaryTap: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: _down ? SegueMotion.fast : SegueMotion.medium,
          curve: _down ? Curves.easeOut : SegueMotion.spring,
          child: child,
        ),
      ),
    );
  }
}

/// Fades and slides a list item in, staggered by its [index].
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = (index * 0.06).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + (delay * 1000).round()),
      curve: Interval(delay / (delay + 0.42), 1, curve: SegueMotion.ease),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Swaps text with a soft slide-up crossfade when it changes.
class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: SegueMotion.medium,
      switchInCurve: SegueMotion.ease,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
