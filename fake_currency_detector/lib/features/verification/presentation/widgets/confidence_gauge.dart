/// Confidence gauge: a 240-degree arc with the app score in the middle.
///
/// Shows the "APP CHECK SCORE" percentage and a caption (for example the
/// verdict text). The arc fills from 0 up to the score when it first appears.
/// Used in results_screen.dart. Colours come from verdict_style.dart.
/// Input: percentage (0-100), arc colours, caption, accent colour.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 240° neon arc gauge that animates from 0 up to [percentage].
///
/// [percentage] is the score (0-100). [colors] is the arc gradient (one or
/// more colours). [caption] is the small text under the number. [accent]
/// colours the caption and the glow behind the number. When [inconclusive]
/// is true the caption shows "(INCONCLUSIVE)" instead. [size] is the width.
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

  /// Score to show, from 0 to 100.
  final int percentage;
  final List<Color> colors;
  /// Text under the number (replaced when [inconclusive] is true).
  final String caption;

  /// Colour for the caption and number glow.
  final Color accent;
  /// When true, show "(INCONCLUSIVE)" instead of [caption].
  final bool inconclusive;

  /// Width of the gauge in logical pixels; height is 0.86 of this.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Animates value from 0 to the score (as 0.0-1.0) over 1.8 seconds.
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
            // Text drawn on top of the arc, pushed down into the arc opening.
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.18),
              child: Column(
                children: [
                  // Small title.
                  Text(
                    'APP CHECK SCORE',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  // Big animated percentage with a soft glow.
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
                  // Caption under the number.
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

/// Paints the gauge: grey track, tick marks, glowing progress arc and tip.
///
/// [value] is the fill amount from 0.0 to 1.0. [colors] is the arc gradient.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.colors});

  final double value;
  final List<Color> colors;

  // The arc starts at 150° (lower left) and sweeps 240° clockwise, which
  // leaves an opening at the bottom for a speedometer look.
  static const double _start = math.pi * 5 / 6; // 150°
  static const double _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.07;
    final center = Offset(size.width / 2, size.width / 2);
    final radius = size.width / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track: the faint full-length arc behind the progress.
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

    // 41 tick marks. Ticks 16 and 34 (of 40) sit at 40% and 85% and are
    // drawn longer and brighter. Ticks already reached are brighter too.
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

    // Nothing more to draw when the score is zero.
    if (value <= 0) return;

    // Length of the filled part of the arc.
    final sweep = _sweep * value;
    final shader = SweepGradient(
      startAngle: _start,
      endAngle: _start + _sweep,
      colors: colors.length == 1 ? [colors.first, colors.first] : colors,
      transform: const GradientRotation(0),
    ).createShader(rect);

    // Glow: a wider, blurred copy of the arc under the sharp one.
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
    // Core: the sharp progress arc.
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

    // Leading spark: a white dot at the end of the filled arc.
    final tip = _start + sweep;
    canvas.drawCircle(
      center + Offset(math.cos(tip), math.sin(tip)) * radius,
      stroke * 0.32,
      Paint()..color = Colors.white,
    );
  }

  // Repaint only when the fill amount or the colours change.
  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.colors != colors;
}
