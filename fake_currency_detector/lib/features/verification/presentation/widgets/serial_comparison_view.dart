import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/feature_check_model.dart';

/// Shows both OCR'd serials as aligned character cells, highlighting every
/// position that differs.
class SerialComparisonView extends StatelessWidget {
  const SerialComparisonView({super.key, required this.comparison});

  final SerialComparisonModel comparison;

  @override
  Widget build(BuildContext context) {
    final pairs = comparison.pairs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, 'SERIAL #1', pairs.map((p) => (p.$1, p.$1 == p.$2))),
        const SizedBox(height: 8),
        _row(context, 'SERIAL #2', pairs.map((p) => (p.$2, p.$1 == p.$2))),
        const SizedBox(height: 10),
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
