/// Animated "scanner" effect: a glowing line moving up and down over a widget.
///
/// Shown over the camera or note image to suggest that scanning is happening.
library;

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

  /// The widget the laser moves over.
  final Widget child;

  /// Colour of the laser line.
  final Color color;

  /// Time for one trip from top to bottom.
  final Duration duration;

  /// When false, the laser is hidden and the animation is stopped.
  final bool active;

  @override
  State<LaserSweep> createState() => _LaserSweepState();
}

/// Holds the animation clock that moves the laser.
class _LaserSweepState extends State<LaserSweep>
    with SingleTickerProviderStateMixin {
  // Runs from 0 to 1 and back; 0 = top, 1 = bottom.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  // Start or stop the animation when [active] changes.
  @override
  void didUpdateWidget(covariant LaserSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  // Free the animation resources when the widget is removed.
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The child sits underneath; the laser is painted on top of it.
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            // Touches pass through the laser to the widgets below.
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

/// Draws the laser line and its glow on the canvas.
class _LaserPainter extends CustomPainter {
  _LaserPainter(this.t, this.color);

  /// Position of the laser: 0 = top edge, 1 = bottom edge.
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Vertical position of the line in pixels.
    final y = size.height * t;

    // Trailing scan wash: a 60 px band above the line that fades in.
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

  // Redraw only when the position or colour changed.
  @override
  bool shouldRepaint(covariant _LaserPainter old) =>
      old.t != t || old.color != color;
}
