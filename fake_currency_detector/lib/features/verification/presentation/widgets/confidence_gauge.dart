import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 240° neon arc gauge that animates from 0 up to [percentage].
class ConfidenceGauge extends StatelessWidget {
  const ConfidenceGauge({
    super.key,
    required this.percentage,
    required this.colors,
    required this.caption,
    required this.accent,
    this.inconclusive = false,
    this.size = 240,
  });

  final int percentage;
  final List<Color> colors;
  final String caption;

  /// Colour for the caption and number glow.
  final Color accent;
  final bool inconclusive;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percentage / 100),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size * 0.86,
          child: CustomPaint(
            painter: _GaugePainter(value: value, colors: colors),
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.18),
              child: Column(
                children: [
                  Text(
                    'APP CHECK SCORE',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(value * 100).round()}%',
                    style: TextStyle(
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(
                          color: accent.withValues(alpha: 0.7),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inconclusive ? '(INCONCLUSIVE)' : caption,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.colors});

  final double value;
  final List<Color> colors;

  static const double _start = math.pi * 5 / 6; // 150°
  static const double _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final center = Offset(size.width / 2, size.width / 2);
    final radius = size.width / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track.
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    // Ticks + threshold markers at 40% and 85%.
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final a = _start + _sweep * t;
      final isThreshold = i == 16 || i == 34;
      final inner = radius - stroke * (isThreshold ? 1.6 : 1.05);
      final outer = radius - stroke * 0.75;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * outer,
        Paint()
          ..strokeWidth = isThreshold ? 2 : 1
          ..color = isThreshold
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: t <= value ? 0.35 : 0.1),
      );
    }

    if (value <= 0) return;

    final sweep = _sweep * value;
    final shader = SweepGradient(
      startAngle: _start,
      endAngle: _start + _sweep,
      colors: colors.length == 1 ? [colors.first, colors.first] : colors,
      transform: const GradientRotation(0),
    ).createShader(rect);

    // Glow.
    canvas.drawArc(
      rect,
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.6
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Core.
    canvas.drawArc(
      rect,
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    // Leading spark.
    final tip = _start + sweep;
    canvas.drawCircle(
      center + Offset(math.cos(tip), math.sin(tip)) * radius,
      stroke * 0.32,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.colors != colors;
}
