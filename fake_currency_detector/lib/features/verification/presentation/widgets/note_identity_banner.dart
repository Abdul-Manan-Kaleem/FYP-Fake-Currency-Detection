/// Note identity banner: says a Pakistani banknote was found and its value.
///
/// Full size it is a glowing card on the results screen
/// (results_screen.dart). Compact it is a one-line pill on the capture
/// screen (capture_screen.dart).
/// Input: the denomination read on the front and/or back (may be null).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/currency_rules.dart';

/// States that the photographed item is a Pakistani banknote and gives its
/// value (for example "Rs 5,000"). YOLO11s is trained only on Pakistani
/// notes, so a note class found on both sides means a Pakistani note.
///
/// [frontValue] and [backValue] are the denominations read on each side
/// (null when not confirmed). [compact] gives a one-line version for the
/// capture steps.
class NoteIdentityBanner extends StatelessWidget {
  const NoteIdentityBanner({
    super.key,
    this.frontValue,
    this.backValue,
    this.compact = false,
  });

  /// Denomination read on the front, or null.
  final int? frontValue;

  /// Denomination read on the back, or null.
  final int? backValue;

  /// True for the one-line pill, false for the full card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Pick the value text and the detail line from what was read:
    // both sides equal, both different, only one side, or neither.
    final agreed = frontValue != null && frontValue == backValue;
    final String value;
    final String detail;
    if (agreed) {
      value = formatRupees(frontValue!);
      detail = 'Same value read on both sides';
    } else if (frontValue != null && backValue != null) {
      value = '${formatRupees(frontValue!)} / ${formatRupees(backValue!)}';
      detail = 'The two sides read different values';
    } else if (frontValue != null || backValue != null) {
      final side = frontValue != null ? 'front' : 'back';
      value = formatRupees((frontValue ?? backValue)!);
      detail = 'Value read on the $side only';
    } else {
      value = 'Value not confirmed';
      detail = 'A Pakistani banknote was found, but its value could not be read';
    }
    // Green when the value is confirmed, amber when unsure or mismatched.
    final color = agreed || (compact && (frontValue ?? backValue) != null)
        ? AppColors.emerald
        : AppColors.amber;

    // Compact version: a one-line pill.
    if (compact) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            color: color.withValues(alpha: 0.10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'PAKISTANI BANKNOTE · $value',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Full version: glass card with icon, heading, value and detail.
    return GlassContainer(
      glowColor: color,
      glowIntensity: 0.2,
      borderColor: color.withValues(alpha: 0.5),
      fill: color.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: color, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAKISTANI BANKNOTE DETECTED',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
