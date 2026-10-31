import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Onyx backdrop with a faint grid and soft neon blooms.
class CyberBackground extends StatelessWidget {
  const CyberBackground({
    super.key,
    required this.child,
    this.accent = AppColors.cyan,
  });

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.onyx, AppColors.onyxDeep],
            ),
          ),
        ),
        const CustomPaint(painter: _GridPainter()),
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

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
