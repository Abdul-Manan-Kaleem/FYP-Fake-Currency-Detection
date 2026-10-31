import 'package:flutter/services.dart';

/// Centralised haptic patterns so feedback feels consistent.
abstract final class Haptics {
  static Future<void> tap() => HapticFeedback.selectionClick();

  static Future<void> capture() => HapticFeedback.mediumImpact();

  static Future<void> success() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  static Future<void> warning() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }

  static Future<void> alert() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }
}
