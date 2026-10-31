import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Frosted-glass surface with a thin border and optional neon outer glow.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.glowColor,
    this.glowIntensity = 0.35,
    this.borderColor,
    this.blur = 16,
    this.fill,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? glowColor;
  final double glowIntensity;
  final Color? borderColor;
  final double blur;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: glowIntensity),
              blurRadius: 28,
              spreadRadius: -6,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: borderColor ?? AppColors.glassBorder,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: fill == null
                    ? [
                        Colors.white.withValues(alpha: 0.07),
                        Colors.white.withValues(alpha: 0.02),
                      ]
                    : [fill!, fill!.withValues(alpha: fill!.a * 0.85)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
