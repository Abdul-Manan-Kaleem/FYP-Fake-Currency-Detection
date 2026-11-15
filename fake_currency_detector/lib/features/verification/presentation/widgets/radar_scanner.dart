/// Radar scanner: a rotating radar sweep with blips, used as a loading visual.
///
/// Shown in the middle of analyzing_screen.dart while the note is checked.
/// Input: optional size and colour (defaults to 220 and cyan).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Rotating radar sweep with fading blips, shown while the engine works.
///
/// [size] is the width and height. [color] tints the rings, beam and blips.
class RadarScanner extends StatefulWidget {
  const RadarScanner({super.key, this.size = 220, this.color = AppColors.cyan});

  /// Width and height of the radar in logical pixels.
  final double size;

  /// Main colour of the radar.
  final Color color;

  @override
  State<RadarScanner> createState() => _RadarScannerState();
}

/// Owns the animation controller that turns the beam.
class _RadarScannerState extends State<RadarScanner>
    with SingleTickerProviderStateMixin {
  // One full turn every 2.4 seconds, repeating forever.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  // Fixed pseudo-random blip positions (angle, radius fraction).
  // A seeded Random keeps the same layout every time.
  static final List<(double, double)> _blips = List.generate(9, (i) {
    final r = math.Random(i * 7919);
    return (r.nextDouble() * 2 * math.pi, 0.25 + r.nextDouble() * 0.65);
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(
            angle: _c.value * 2 * math.pi,
            color: widget.color,
            blips: _blips,
          ),
        ),
      ),
    );
  }
}

/// Draws the rings, glow, sweep beam and blips.
///
/// [angle] is the beam angle in radians, [color] the main colour, [blips]
/// the (angle, distance fraction) of each dot.
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.angle, required this.color, required this.blips});

  final double angle;
  final Color color;
  final List<(double, double)> blips;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Grid: 4 circles plus a cross through the centre.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.22);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(c, r * i / 4, ring);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), ring);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), ring);

    // Outer glow ring.
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Sweep wedge: the canvas is rotated by the beam angle, then a fading
    // gradient (brightest at its end) and a bright line are drawn.
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            Colors.transparent,
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.45),
          ],
          stops: const [0.0, 0.75, 1.0],
        ).createShader(rect),
    );
    canvas.drawLine(
      c,
      Offset(c.dx + r, c.dy),
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.4)!
        ..strokeWidth = 2,
    );
    canvas.restore();

    // Blips light up as the beam passes and then fade out.
    // delta = how far the beam has moved past the blip (0 to 2π); the blip
    // fades to nothing after about 1.2π (216°).
    for (final (a, f) in blips) {
      var delta = (angle - a) % (2 * math.pi);
      if (delta < 0) delta += 2 * math.pi;
      final alpha = (1 - delta / (math.pi * 1.2)).clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * f;
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(p, 2.4, Paint()..color = color.withValues(alpha: alpha));
    }

    // Centre dot.
    canvas.drawCircle(c, 4, Paint()..color = color);
  }

  // Repaint only when the beam has moved.
  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.angle != angle;
}
