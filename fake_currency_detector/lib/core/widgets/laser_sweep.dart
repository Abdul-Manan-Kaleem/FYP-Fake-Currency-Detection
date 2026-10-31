import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A glowing horizontal laser line that sweeps vertically over [child].
class LaserSweep extends StatefulWidget {
  const LaserSweep({
    super.key,
    required this.child,
    this.color = AppColors.cyan,
    this.duration = const Duration(milliseconds: 2200),
    this.active = true,
  });

  final Widget child;
  final Color color;
  final Duration duration;
  final bool active;

  @override
  State<LaserSweep> createState() => _LaserSweepState();
}

class _LaserSweepState extends State<LaserSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LaserSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _LaserPainter(
                    Curves.easeInOutSine.transform(_c.value),
                    widget.color,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * t;

    // Trailing scan wash.
    final trail = Rect.fromLTRB(0, y - 60, size.width, y);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, color.withValues(alpha: 0.18)],
        ).createShader(trail),
    );

    // Glow + core beam.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.5)!
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _LaserPainter old) =>
      old.t != t || old.color != color;
}
