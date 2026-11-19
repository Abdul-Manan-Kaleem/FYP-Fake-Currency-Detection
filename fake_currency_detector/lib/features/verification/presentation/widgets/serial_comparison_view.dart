/// Serial comparison view: the two read serial numbers side by side.
///
/// Each character is a small cell. Matching characters are green and
/// differing ones are red. A summary line says if the serials match.
/// Used inside inspection_tile.dart when a check has a serial comparison.
/// Input: a SerialComparisonModel (the two serials and their pairs).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/feature_check_model.dart';

/// Shows both OCR'd serials as aligned character cells, highlighting every
/// position that differs.
///
/// [comparison] holds both serials, aligned in character pairs.
class SerialComparisonView extends StatelessWidget {
  const SerialComparisonView({super.key, required this.comparison});

  /// The two OCR'd serials and the result of comparing them.
  final SerialComparisonModel comparison;

  @override
  Widget build(BuildContext context) {
    // Each pair is (char from serial 1, char from serial 2).
    final pairs = comparison.pairs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two rows of cells, one per serial. A cell is ok if both match.
        _row(context, 'SERIAL #1', pairs.map((p) => (p.$1, p.$1 == p.$2))),
        const SizedBox(height: 8),
        _row(context, 'SERIAL #2', pairs.map((p) => (p.$2, p.$1 == p.$2))),
        const SizedBox(height: 10),
        // Summary line: link icon plus match / mismatch text.
        Row(
          children: [
            Icon(
              comparison.matches ? Icons.link_rounded : Icons.link_off_rounded,
              size: 16,
              color: comparison.matches ? AppColors.emerald : AppColors.crimson,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                comparison.matches
                    ? 'Exact match · ${comparison.first.length} characters'
                    : '${comparison.mismatchCount} mismatched position(s)'
                        '${comparison.lengthMatches ? '' : ' · length '
                            '${comparison.first.length} vs ${comparison.second.length}'}',
                style: TextStyle(
                  fontSize: 12,
                  color: comparison.matches
                      ? AppColors.emerald
                      : AppColors.crimson,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds one labelled row of character cells.
  ///
  /// [label] is the row title. [cells] is each character (null = missing,
  /// shown as "∅") and whether it matches the other serial.
  Widget _row(
    BuildContext context,
    String label,
    Iterable<(String?, bool)> cells,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final (ch, ok) in cells)
              Container(
                width: 24,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: ok
                      ? AppColors.emerald.withValues(alpha: 0.08)
                      : AppColors.crimson.withValues(alpha: 0.22),
                  border: Border.all(
                    color: ok
                        ? AppColors.emerald.withValues(alpha: 0.35)
                        : AppColors.crimson,
                  ),
                ),
                child: Text(
                  ch ?? '∅',
                  style: TextStyle(
                    fontFamily: AppTheme.mono,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: ch == null
                        ? AppColors.textMuted
                        : ok
                            ? AppColors.textPrimary
                            : AppColors.crimson,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
