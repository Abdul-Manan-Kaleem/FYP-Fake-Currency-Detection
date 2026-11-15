/// Reusable "frosted glass" card used to hold content across the app.
///
/// It blurs whatever is behind it and adds a thin border and optional glow.
library;

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

  /// Content shown inside the card.
  final Widget child;

  /// Space between the card edge and the content.
  final EdgeInsetsGeometry padding;

  /// How rounded the corners are.
  final double borderRadius;

  /// Colour of the outer glow; no glow when null.
  final Color? glowColor;

  /// Strength of the glow, from 0 (none) to 1 (full).
  final double glowIntensity;

  /// Border colour; uses the default glass border when null.
  final Color? borderColor;

  /// How strongly the background behind the card is blurred.
  final double blur;

  /// Solid fill colour; uses a faint white gradient when null.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    // Outer layer draws the optional glow (a coloured shadow).
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
      // Clip to rounded corners, then blur what is behind the card.
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
              // Default fill fades from 7% to 2% white; a custom fill
              // fades to 85% of its own opacity.
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
