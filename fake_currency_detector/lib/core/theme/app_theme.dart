/// The app-wide theme: fonts, colours and default styles for common widgets.
///
/// main.dart passes [AppTheme.dark] to MaterialApp, so every screen uses it.
library;

import 'package:flutter/material.dart';

import '../utils/page_transitions.dart';
import 'app_colors.dart';

/// Holds the dark theme used by the whole app.
abstract final class AppTheme {
  /// Monospace stack used for serial numbers and telemetry readouts.
  static const String mono = 'monospace';

  /// The complete dark [ThemeData] for the app.
  static ThemeData get dark {
    // Step 1: Start from a basic dark Material 3 theme with our colours.
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.onyx,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.emerald,
        error: AppColors.crimson,
        surface: AppColors.surface,
        onPrimary: AppColors.onyx,
        onSurface: AppColors.textPrimary,
      ),
    );

    // Step 2: Add our own text styles and widget styles on top of the base.
    return base.copyWith(
      // Text sizes and weights for headings, titles, body and small labels.
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            headlineMedium: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textPrimary,
            ),
            titleLarge: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: AppColors.textPrimary,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: AppColors.textPrimary,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
            labelSmall: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.textSecondary,
            ),
          ),
      // Top bar: see-through, no shadow, centred title.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: AppColors.textPrimary,
        ),
      ),
      // Small pop-up messages at the bottom of the screen.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      // Bottom sheets are see-through so our own glass panels show.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      // On/off switches: cyan when on, grey when off.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.cyan
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.cyan.withValues(alpha: 0.3)
              : AppColors.surfaceHigh,
        ),
      ),
      // Text input boxes: faint glass fill, cyan border when focused.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cyan),
        ),
      ),
      // Use our custom page animation on Android and iOS.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CyberPageTransitionsBuilder(),
          TargetPlatform.iOS: CyberPageTransitionsBuilder(),
        },
      ),
    );
  }
}
