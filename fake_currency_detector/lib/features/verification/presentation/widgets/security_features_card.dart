/// Security features card: one clear row for every feature a note must show.
///
/// Rows: security dots, security lines, security thread, SBP seals, serial
/// numbers and the printed year. Each row says whether the feature was found,
/// how many were found against how many the denomination should have, and
/// whether it passed. A missing required feature is shown in red because the
/// app calls such a note FAKE.
///
/// Used in results_screen.dart, right below the verdict.
/// Input: the finished [VerificationResultModel].
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../data/models/feature_check_model.dart';
import '../../data/models/note_analysis_model.dart';
import '../../data/models/verification_result_model.dart';
import '../../domain/currency_rules.dart';
import 'verdict_style.dart';

/// Lists the security features and what the app found for each.
class SecurityFeaturesCard extends StatelessWidget {
  const SecurityFeaturesCard({super.key, required this.result});

  /// The result whose checks and counts are listed.
  final VerificationResultModel result;

  /// The check with this id, or null when the engine did not run it.
  FeatureCheckModel? _check(FeatureCheckId id) =>
      result.checks.where((c) => c.id == id).firstOrNull;

  /// Row for security dots or security lines.
  ///
  /// [kind] says which mark this row is about. The denomination decides how
  /// many are expected: its own mark type must be present, the other type
  /// must be absent (Rs 10 has neither).
  _Row _markRow(String name, FeatureDetectionModel? found, DenominationMark kind) {
    final spec = CurrencyRules.denominations[result.denomination];
    final word = kind == DenominationMark.dots ? 'dots' : 'lines';
    if (found == null) {
      return _Row(name, CheckStatus.skipped, 'Not checked');
    }
    if (spec == null) {
      return _Row(name, CheckStatus.inconclusive, 'Note value not confirmed');
    }
    final expected = spec.mark == kind ? spec.markCount : 0;
    final seen = found.observedMarks;
    if (expected == 0) {
      return seen > 0
          ? _Row(name, CheckStatus.fail,
              'Found, but this note should not have $word')
          : _Row(name, CheckStatus.notApplicable, 'Not on this note');
    }
    if (seen == 0) {
      return found.uncertainCount > 0
          ? _Row(name, CheckStatus.inconclusive,
              'Only faintly seen · expected $expected')
          : _Row(name, CheckStatus.fail, 'MISSING · expected $expected');
    }
    // Strict rule: exactly the required number, no more and no fewer.
    if (seen != expected) {
      return _Row(name, CheckStatus.fail, '$seen found · required $expected');
    }
    return _Row(name, CheckStatus.pass, 'Found · $seen of $expected');
  }

  /// Row built from one of the engine's checks (its status and summary).
  _Row _fromCheck(String name, FeatureCheckId id) {
    final c = _check(id);
    if (c == null) return _Row(name, CheckStatus.skipped, 'Not checked');
    return _Row(name, c.status, c.summary);
  }

  @override
  Widget build(BuildContext context) {
    final front = result.analysis?.front;
    final rows = [
      _markRow('Security dots', front?.securityDots, DenominationMark.dots),
      _markRow('Security lines', front?.securityLines, DenominationMark.lines),
      _fromCheck('Security thread', FeatureCheckId.securityThread),
      _fromCheck('SBP seals', FeatureCheckId.sbpSeals),
      _fromCheck('Serial numbers', FeatureCheckId.serialNumber),
      _fromCheck('Printed year', FeatureCheckId.printedYear),
      // Picture checks: Quaid-e-Azam portrait (front) and monument (back).
      _fromCheck('Quaid-e-Azam portrait (front)', FeatureCheckId.portrait),
      _fromCheck('Monument (back)', FeatureCheckId.monument),
    ];
    final missing = rows.any((r) => r.status == CheckStatus.fail);

    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Short rule, so the user knows why a red row means FAKE.
          Text(
            missing
                ? 'A required security feature is missing, so this note is '
                    'treated as FAKE.'
                : 'Every security feature this note must show is listed '
                    'below.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in rows) _RowTile(row: r),
        ],
      ),
    );
  }
}

/// One line of the card: feature name, what was found, and a status.
class _Row {
  const _Row(this.name, this.status, this.detail);

  final String name;
  final CheckStatus status;
  final String detail;
}

/// Draws a [_Row]: coloured status icon, name, detail text and status word.
class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final color = row.status.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon in a small circle.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Icon(row.status.icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          // Name and detail.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Status word on the right.
          Text(
            row.status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
