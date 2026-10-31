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

  final Widget child;
  final Color color;
  final double size;
  final Duration duration;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size * 1.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ripple ring.
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
