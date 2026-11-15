/// Reusable page background: dark gradient, faint grid and coloured glows.
///
/// Screens put their content inside it so all pages share the same look.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Onyx backdrop with a faint grid and soft neon blooms.
class CyberBackground extends StatelessWidget {
  const CyberBackground({
    super.key,
    required this.child,
    this.accent = AppColors.cyan,
  });

  /// The page content drawn on top of the background.
  final Widget child;

  /// Colour of the glow in the top-left corner (changes with an animation).
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Layers from back to front: gradient, grid, accent glow, violet glow,
    // then the page content.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: dark gradient from top to bottom.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.onyx, AppColors.onyxDeep],
            ),
          ),
        ),
        // Layer 2: faint grid lines.
        const CustomPaint(painter: _GridPainter()),
        // Layer 3: accent glow top-left; fades smoothly when [accent] changes.
        AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, -1.1),
              radius: 1.1,
              colors: [accent.withValues(alpha: 0.16), Colors.transparent],
            ),
          ),
        ),
        // Layer 4: fixed violet glow at the bottom-right.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.2, 1.1),
              radius: 1.0,
              colors: [
                AppColors.violet.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Draws the faint grid by hand on the canvas.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Thin white lines at about 2.5% opacity, so the grid is barely visible.
    // Lines are drawn every 28 pixels, first vertical, then horizontal.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  // The grid never changes, so it never needs to be redrawn.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
