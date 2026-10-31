import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/feature_check_model.dart';
import '../../data/models/verification_result_model.dart';

extension VerdictStyle on VerificationVerdict {
  Color get color => switch (this) {
        VerificationVerdict.real => AppColors.emerald,
        VerificationVerdict.suspicious => AppColors.amber,
        VerificationVerdict.fake => AppColors.crimson,
        VerificationVerdict.notBanknote => AppColors.crimson,
        VerificationVerdict.unableToVerify ||
        VerificationVerdict.incomplete =>
          AppColors.amber,
      };

  /// Gauge gradient. Suspicious blends amber into crimson.
  List<Color> get gaugeColors => switch (this) {
        VerificationVerdict.real => const [Color(0xFF00B85C), AppColors.emerald],
        VerificationVerdict.suspicious => const [AppColors.amber, AppColors.crimson],
        VerificationVerdict.fake => const [AppColors.crimson, AppColors.crimson],
        _ => const [AppColors.amber, AppColors.amber],
      };

  IconData get icon => switch (this) {
        VerificationVerdict.real => Icons.verified_rounded,
        VerificationVerdict.suspicious => Icons.report_problem_rounded,
        VerificationVerdict.fake => Icons.gpp_bad_rounded,
        VerificationVerdict.unableToVerify => Icons.blur_on_rounded,
        VerificationVerdict.incomplete => Icons.flip_rounded,
        VerificationVerdict.notBanknote => Icons.do_not_disturb_alt_rounded,
      };
}

extension CheckStatusStyle on CheckStatus {
  Color get color => switch (this) {
        CheckStatus.pass => AppColors.emerald,
        CheckStatus.fail => AppColors.crimson,
        CheckStatus.inconclusive => AppColors.amber,
        CheckStatus.skipped => AppColors.textMuted,
        CheckStatus.notApplicable => AppColors.textMuted,
        CheckStatus.warning => AppColors.amber,
      };

  IconData get icon => switch (this) {
        CheckStatus.pass => Icons.check_rounded,
        CheckStatus.fail => Icons.close_rounded,
        CheckStatus.inconclusive => Icons.question_mark_rounded,
        CheckStatus.skipped => Icons.remove_rounded,
        CheckStatus.notApplicable => Icons.block_rounded,
        CheckStatus.warning => Icons.warning_amber_rounded,
      };

  String get label => switch (this) {
        CheckStatus.pass => 'PASS',
        CheckStatus.fail => 'FAIL',
        CheckStatus.inconclusive => 'UNCLEAR',
        CheckStatus.skipped => 'SKIPPED',
        CheckStatus.notApplicable => 'N/A',
        CheckStatus.warning => 'WARNING',
      };
}

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
        FeatureCheckId.microprint => Icons.zoom_in_rounded,
        FeatureCheckId.monument => Icons.account_balance_outlined,
      };
}
