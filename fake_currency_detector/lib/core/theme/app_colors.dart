/// All colours used by the app, defined once so the look stays consistent.
///
/// Used by the theme and by the custom widgets in lib/core/widgets.
library;

import 'package:flutter/material.dart';

/// Cyber / fintech palette used across the app.
abstract final class AppColors {
  // Dark background and card colours.
  /// Main dark page background.
  static const Color onyx = Color(0xFF0D1117);

  /// Even darker shade (used for the system navigation bar).
  static const Color onyxDeep = Color(0xFF070A0F);

  /// Card / panel background.
  static const Color surface = Color(0xFF161B22);

  /// Slightly lighter panel colour for raised items.
  static const Color surfaceHigh = Color(0xFF1F2630);

  // Accent colours.
  /// Green accent (used for good / positive results).
  static const Color emerald = Color(0xFF00E676);

  /// Red accent (used for errors and bad results).
  static const Color crimson = Color(0xFFFF1744);

  /// Orange-yellow accent (used for warnings).
  static const Color amber = Color(0xFFFFAB00);

  /// Blue-green accent; the main brand colour.
  static const Color cyan = Color(0xFF00E5FF);

  /// Purple accent.
  static const Color violet = Color(0xFF7C4DFF);

  // Text colours, from strongest to faintest.
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF545D68);

  // "Glass" look: a very faint white fill (about 5% opaque) and thin border.
  static const Color glassFill = Color(0x0DFFFFFF);
  static const Color glassBorder = Colors.white10;
}
