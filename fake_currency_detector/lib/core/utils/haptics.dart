/// Phone vibration ("haptic") patterns used for button and result feedback.
///
/// Keeping them here means every screen vibrates in the same way.
library;

import 'package:flutter/services.dart';

/// Centralised haptic patterns so feedback feels consistent.
abstract final class Haptics {
  /// Tiny click for ordinary button taps.
  static Future<void> tap() => HapticFeedback.selectionClick();

  /// Medium buzz when a photo is captured.
  static Future<void> capture() => HapticFeedback.mediumImpact();

  /// Light then medium buzz (90 ms apart) for a good result.
  static Future<void> success() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  /// Two heavy buzzes (120 ms apart) to warn the user.
  static Future<void> warning() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }

  /// Three quick heavy buzzes for the strongest alert.
  static Future<void> alert() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }
}
