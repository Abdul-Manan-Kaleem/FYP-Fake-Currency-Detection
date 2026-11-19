/// Animated circular badge with a pulsing glow and an expanding ring.
///
/// Used to draw attention to an icon, for example on a result or status view.
library;

import 'package:flutter/material.dart';

/// Wraps [child] in a softly pulsing circular glow.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({
    super.key,
    required this.child,
    required this.color,
    this.size = 96,
    this.duration = const Duration(milliseconds: 1400),
  });

  /// Widget shown in the middle of the circle (for example an icon).
  final Widget child;

  /// Colour of the glow, ring and border.
  final Color color;

  /// Diameter of the inner circle.
  final double size;

  /// Time for one full pulse.
  final Duration duration;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

/// Holds the looping animation clock for [PulsingGlow].
class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  // Runs from 0 to 1 and then restarts, forever.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  // Free the animation resources when the widget is removed.
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reserve 1.6x the circle size so the ring has room to grow.
    return SizedBox.square(
      dimension: widget.size * 1.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Progress of the current pulse, from 0 to 1.
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ripple ring: grows up to 1.6x and fades out.
              Container(
                width: widget.size * (1 + 0.6 * t),
                height: widget.size * (1 + 0.6 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: (1 - t) * 0.6),
                    width: 2,
                  ),
                ),
              ),
              // Inner circle with the child; its shadow is brightest at the
              // middle of the pulse (t = 0.5) and dimmest at the ends.
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.12),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(
                        alpha: 0.35 + 0.25 * (1 - (2 * t - 1).abs()),
                      ),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              ),
            ],
          );
        },
        child: Center(child: widget.child),
      ),
    );
  }
}
