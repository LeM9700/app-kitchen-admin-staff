import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Staggered fade+slide entrance for back-office list/grid rows, following
/// the motion timing this app standardized on: ~200-250ms fade+slideY per
/// item, offset by ~30-50ms per index so a list "cascades" in rather than
/// popping in all at once. Deliberately short — this is an operations
/// tool, not a marketing surface.
///
/// [index] is clamped so long lists don't produce an increasingly long
/// tail of delay; past [maxStaggeredIndex] every row animates together.
///
/// The per-index offset is passed as an effect-level `delay` (folded into
/// the single ticker-driven AnimationController's timeline), not
/// `Animate.delay` (the widget-level parameter, which defers the whole
/// controller via a real `Future.delayed`/`Timer`). Effect-level delay
/// keeps everything on the normal frame clock that `tester.pump(duration)`
/// advances directly, so no async Timer is left pending in tests.
extension StaggeredEntrance on Widget {
  Widget staggeredEntrance(
    int index, {
    int maxStaggeredIndex = 12,
    Duration stagger = const Duration(milliseconds: 35),
  }) {
    // Respects reduce-motion (accessibility setting, and how golden/widget
    // tests opt out of decorative animation so they capture settled UI).
    if (WidgetsBinding.instance.disableAnimations) {
      return this;
    }
    final delay = stagger * index.clamp(0, maxStaggeredIndex);
    return animate()
        .fadeIn(delay: delay, duration: 220.ms, curve: Curves.easeOut)
        .slideY(
          delay: delay,
          begin: 0.06,
          end: 0,
          duration: 220.ms,
          curve: Curves.easeOut,
        );
  }
}
