/// Verdict styles: colours, icons and labels for verdicts and check statuses.
///
/// These are extensions, so code can write verdict.color or status.icon.
/// Used by verdict_badge.dart, inspection_tile.dart and results_screen.dart.
/// Input: none (they extend the enums VerificationVerdict, CheckStatus and
/// FeatureCheckId).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/feature_check_model.dart';
import '../../data/models/verification_result_model.dart';

/// Colour, gauge colours and icon for each [VerificationVerdict].
///
/// Green means real, amber means the note could not be verified, red means
/// fake or not a banknote.
extension VerdictStyle on VerificationVerdict {
  /// Main colour of the verdict.
  Color get color => switch (this) {
        VerificationVerdict.real => AppColors.emerald,
        VerificationVerdict.fake => AppColors.crimson,
        VerificationVerdict.notBanknote => AppColors.crimson,
        VerificationVerdict.unableToVerify ||
        VerificationVerdict.incomplete =>
          AppColors.amber,
      };

  /// Gauge gradient: green for real, red for fake, amber otherwise.
  List<Color> get gaugeColors => switch (this) {
        VerificationVerdict.real => const [Color(0xFF00B85C), AppColors.emerald],
        VerificationVerdict.fake => const [AppColors.crimson, AppColors.crimson],
        _ => const [AppColors.amber, AppColors.amber],
      };

  /// Icon of the verdict.
  IconData get icon => switch (this) {
        VerificationVerdict.real => Icons.verified_rounded,
        VerificationVerdict.fake => Icons.gpp_bad_rounded,
        VerificationVerdict.unableToVerify => Icons.blur_on_rounded,
        VerificationVerdict.incomplete => Icons.flip_rounded,
        VerificationVerdict.notBanknote => Icons.do_not_disturb_alt_rounded,
      };
}

/// Colour, icon and short label for each [CheckStatus] of a feature check.
extension CheckStatusStyle on CheckStatus {
  /// Colour of the status (green pass, red fail, amber unclear/warning,
  /// grey skipped or not applicable).
  Color get color => switch (this) {
        CheckStatus.pass => AppColors.emerald,
        CheckStatus.fail => AppColors.crimson,
        CheckStatus.inconclusive => AppColors.amber,
        CheckStatus.skipped => AppColors.textMuted,
        CheckStatus.notApplicable => AppColors.textMuted,
        CheckStatus.warning => AppColors.amber,
      };

  /// Icon of the status.
  IconData get icon => switch (this) {
        CheckStatus.pass => Icons.check_rounded,
        CheckStatus.fail => Icons.close_rounded,
        CheckStatus.inconclusive => Icons.question_mark_rounded,
        CheckStatus.skipped => Icons.remove_rounded,
        CheckStatus.notApplicable => Icons.block_rounded,
        CheckStatus.warning => Icons.warning_amber_rounded,
      };

  /// Short upper-case word shown on the tile.
  String get label => switch (this) {
        CheckStatus.pass => 'PASS',
        CheckStatus.fail => 'FAIL',
        CheckStatus.inconclusive => 'UNCLEAR',
        CheckStatus.skipped => 'SKIPPED',
        CheckStatus.notApplicable => 'N/A',
        CheckStatus.warning => 'WARNING',
      };
}

/// Icon for each security feature check (serial number, seal, thread, etc.).
extension FeatureCheckIcon on FeatureCheckId {
  IconData get icon => switch (this) {
        FeatureCheckId.denomination => Icons.payments_outlined,
        FeatureCheckId.serialNumber => Icons.pin_outlined,
        FeatureCheckId.sbpSeals => Icons.workspace_premium_outlined,
        FeatureCheckId.linesDots => Icons.more_horiz_rounded,
        FeatureCheckId.securityThread => Icons.linear_scale_rounded,
        FeatureCheckId.printedYear => Icons.event_note_outlined,
        FeatureCheckId.surfaceAnomaly => Icons.blur_linear_rounded,
        FeatureCheckId.counterfeitCnn => Icons.psychology_outlined,
        FeatureCheckId.smallCnn => Icons.verified_user_outlined,
        FeatureCheckId.microprint => Icons.zoom_in_rounded,
        FeatureCheckId.monument => Icons.account_balance_outlined,
        FeatureCheckId.portrait => Icons.face_retouching_natural_outlined,
      };
}
