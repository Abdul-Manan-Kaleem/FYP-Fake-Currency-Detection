import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cyber_background.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/utils/page_transitions.dart';
import '../../../scanner/presentation/controllers/capture_controller.dart';
import '../../../scanner/presentation/screens/microprint_camera_screen.dart';
import '../../data/on_device/image_preprocessor.dart';
import '../../data/models/confidence_score_model.dart';
import '../../data/models/feature_check_model.dart';
import '../../data/models/note_analysis_model.dart';
import '../../data/models/verification_result_model.dart';
import '../../domain/currency_rules.dart';
import '../controllers/verification_controller.dart';
import '../widgets/confidence_gauge.dart';
import '../widgets/detection_overlay.dart';
import '../widgets/inspection_tile.dart';
import '../widgets/note_identity_banner.dart';
import '../widgets/security_features_card.dart';
import '../widgets/verdict_badge.dart';
import '../widgets/verdict_style.dart';

/// Results screen ("DIAGNOSTIC REPORT") of the Pakistani Currency Note
/// Screening System.
///
/// Flow: capture front and back photos -> AnalyzingScreen runs the on-device
/// check -> this screen shows the outcome. The close button, the back
/// gesture and the bottom button all return to the first screen.
///
/// What it shows, from top to bottom:
///  1. Banner: is it a Pakistani banknote, and which value.
///  2. Confidence gauge and verdict badge.
///  3. A red "fake" banner (only when the verdict is fake).
///  4. Summary card: plain-language result, top problems, what to do.
///  5. Optional notices: partial check, score penalty, retake help,
///     and the edge-microprint close-up offer.
///  6. "What we found on your note": the photos with boxes marked on
///     everything the detector found.
///  7. Inspection checklist, problems first.
///  8. Analyst notes (only for a conclusive result).
///  9. Technical details, collapsed until the user opens them.
/// A fixed button at the bottom lets the user scan another note.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({
    super.key,
    required this.result,
    this.frontImagePath,
    this.backImagePath,
  });

  /// Result passed in by AnalyzingScreen. build() prefers the newest result
  /// from the controller (see there).
  final VerificationResultModel result;

  /// Captured photos, used to draw YOLO's boxes on the results screen.
  final String? frontImagePath;
  final String? backImagePath;

  /// Clears the old result and photos, then goes back to the first screen
  /// so a new note can be scanned.
  void _scanAnother(BuildContext context, WidgetRef ref) {
    ref.read(verificationControllerProvider.notifier).reset();
    ref.read(captureControllerProvider.notifier).reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follows live updates (e.g. after a microprint close-up).
    final result =
        ref.watch(verificationControllerProvider).result ?? this.result;
    final verdict = result.verdict;
    // The microprint check, if present (null when the list has none).
    final microprintCheck = result.checks
        .where((c) => c.id == FeatureCheckId.microprint)
        .firstOrNull;
    // Colour that matches the verdict; used for glow and accents.
    final color = verdict.color;
    // True when the app could not decide (retake, both sides needed, etc.).
    final inconclusive = !verdict.isConclusive;

    // PopScope: the phone back gesture does not just close the screen. It
    // runs _scanAnother so the old result is cleared first.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _scanAnother(context, ref);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DIAGNOSTIC REPORT'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => _scanAnother(context, ref),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: CyberBackground(
          accent: color,
          child: SafeArea(
            bottom: false,
            child: ListView(
              // 120 px at the bottom keeps the last item clear of the
              // fixed bottom button.
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // ORDER OF THIS SCREEN (top to bottom):
                //  1. the final verdict (gauge, REAL / FAKE badge, summary),
                //  2. the security features list,
                //  3. the checklist and notes,
                //  4. the scanned photographs of the note, at the bottom.
                //
                // 1. Final verdict. Round gauge with the confidence percentage
                Center(
                  child: ConfidenceGauge(
                    percentage: result.confidence.percentage,
                    colors: verdict.gaugeColors,
                    caption: verdict.gaugeCaption,
                    accent: color,
                    inconclusive: inconclusive,
                  ),
                ),
                // Verdict label (REAL or FAKE; or the retake states)
                Center(child: VerdictBadge(verdict: verdict)),
                const SizedBox(height: 20),
                // Red banner, only when the note is fake because of a
                // photocopy, a wrong monument on the back or a wrong
                // Quaid-e-Azam portrait on the front. (Other fake reasons are
                // listed in the summary and the features list.)
                if (verdict == VerificationVerdict.fake &&
                    (result.analysis?.rejectionKind == 'photocopy' ||
                        result.checks.any((c) =>
                            (c.id == FeatureCheckId.monument ||
                                c.id == FeatureCheckId.portrait) &&
                            c.status == CheckStatus.fail))) ...[
                  result.analysis?.rejectionKind == 'photocopy'
                      ? const _FakeBanner(
                          english:
                              'This looks like a photocopy or printout on paper.',
                        )
                      : result.checks.any((c) =>
                              c.id == FeatureCheckId.monument &&
                              c.status == CheckStatus.fail)
                          ? _FakeBanner(
                              english: 'Backside monument mismatch: Rs '
                                  '${result.denomination ?? ''} must show '
                                  '${CurrencyRules.monuments[result.denomination] ?? 'its monument'}.',
                            )
                          : _FakeBanner(
                              english: 'Front portrait mismatch: the '
                                  'Quaid-e-Azam portrait side does not match a '
                                  'Rs ${result.denomination ?? ''} note.',
                            ),
                  const SizedBox(height: 16),
                ],
                // Summary in plain words: what happened and what to do
                _SummaryCard(result: result),
                // Which note it is: Pakistani banknote and its value
                const SizedBox(height: 16),
                NoteIdentityBanner(
                  frontValue: result.analysis?.front?.denomination,
                  backValue: result.analysis?.back?.denomination,
                ),
                // 2. Security features: one row each (dots, lines, thread,
                // seals, serial numbers, year). Shown when checks ran.
                if (result.checks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'SECURITY FEATURES'),
                  const SizedBox(height: 10),
                  SecurityFeaturesCard(result: result),
                ],
                // Notice listing checks that did not run (only when the
                // verdict is conclusive)
                if (!inconclusive &&
                    result.checks.any(
                      (c) => c.status == CheckStatus.skipped,
                    )) ...[
                  const SizedBox(height: 16),
                  _PartialBanner(
                    skipped: [
                      for (final c in result.checks)
                        if (c.status == CheckStatus.skipped) c,
                    ],
                  ),
                ],
                // Explains why the score was lowered, if a penalty applied
                if (result.confidence.penalty != PenaltyType.none) ...[
                  const SizedBox(height: 16),
                  _PenaltyBanner(score: result.confidence),
                ],
                // Retake help when the app could not decide
                if (inconclusive) ...[
                  const SizedBox(height: 16),
                  _InconclusivePanel(result: result),
                ],
                // Offer a close-up photo when the microprint check was
                // skipped or unclear
                if (microprintCheck != null &&
                    (microprintCheck.status == CheckStatus.skipped ||
                        microprintCheck.status ==
                            CheckStatus.inconclusive)) ...[
                  const SizedBox(height: 16),
                  _MicroprintCloseUpCard(
                    denomination: result.denomination ?? 0,
                    summary: microprintCheck.summary,
                  ),
                ],
                // 3. Inspection checklist; header shows "passed/applicable"
                if (result.checks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'INSPECTION CHECKLIST',
                    trailing:
                        '${result.passedCount}/${result.applicableCount} PASSED',
                  ),
                  const SizedBox(height: 10),
                  // Checklist, problems first: fail, unclear, warning, then
                  // passes, then checks that did not run or do not apply.
                  // Failed tiles start open so the reason is visible at once.
                  for (final (i, c) in _problemsFirst(result.checks).indexed)
                    _StaggeredIn(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InspectionTile(
                          check: c,
                          initiallyExpanded: c.failed,
                        ),
                      ),
                    ),
                ],
                // Analyst notes: extra messages, only for a conclusive result
                // (the retake panel already shows them otherwise)
                if (!inconclusive && result.messages.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const _SectionHeader(title: 'ANALYST NOTES'),
                  const SizedBox(height: 10),
                  GlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final m in result.messages) _Bullet(text: m),
                      ],
                    ),
                  ),
                ],
                // 4. The scanned note, at the bottom: the analysed photographs
                // with a mark on everything the detector found. Front first,
                // then back; a side with no detections is left out.
                if (result.analysis?.detections.isNotEmpty ?? false) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'SCANNED NOTE'),
                  const SizedBox(height: 6),
                  const Text(
                    'Each box marks something the scanner found: the note '
                    'value, SBP seals, serial numbers, the printed year, the '
                    'security thread, and the security lines or dots. The '
                    'chips list how many of each were found.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final (key, label, path) in [
                    ('front', 'FRONT', frontImagePath),
                    ('back', 'BACK', backImagePath),
                  ])
                    if (result.analysis!.detections[key] case final d?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DetectionOverlayCard(
                          side: label,
                          imagePath: path,
                          detections: d,
                        ),
                      ),
                ],
                // Technical details (collapsed): engine, raw score, time and
                // stage timings. Developer detail stays out of the way until
                // asked for. The Theme hides the divider lines.
                const SizedBox(height: 14),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    iconColor: AppColors.cyan,
                    collapsedIconColor: AppColors.textMuted,
                    title: Text(
                      'TECHNICAL DETAILS',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    children: [
                      Text(
                        'Engine: ${result.source.toUpperCase()} · '
                        'Raw score ${result.confidence.rawScore.toStringAsFixed(1)} · '
                        '${TimeOfDay.fromDateTime(result.analyzedAt).format(context)}'
                        '${_timings(result)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Fixed bottom button. The label says RETAKE when the note could
        // not be verified or a side is missing; otherwise SCAN ANOTHER.
        bottomNavigationBar: _ActionBar(
          label:
              verdict == VerificationVerdict.unableToVerify ||
                  verdict == VerificationVerdict.incomplete
              ? 'RETAKE PHOTOS'
              : 'SCAN ANOTHER NOTE',
          color: inconclusive ? AppColors.cyan : color,
          onPressed: () => _scanAnother(context, ref),
        ),
      ),
    );
  }
}

/// Builds the extra line for "Technical details": how long each on-device
/// stage took, in milliseconds. Returns an empty string if none were saved.
/// (Used for performance logging, checklist item 18.)
String _timings(VerificationResultModel r) {
  final t = r.analysis?.timingsMs ?? const {};
  if (t.isEmpty) return '';
  final parts = t.entries.map((e) => '${e.key} ${e.value} ms').join(' · ');
  return '\n$parts';
}

/// Sort order for a check status: smaller number = shown earlier.
/// Problems (fail, unclear, warning) come before passes.
int _statusRank(CheckStatus s) => switch (s) {
      CheckStatus.fail => 0,
      CheckStatus.inconclusive => 1,
      CheckStatus.warning => 2,
      CheckStatus.pass => 3,
      CheckStatus.skipped => 4,
      CheckStatus.notApplicable => 5,
    };

/// Checks ordered fail → unclear → warning → pass → skipped → N/A, keeping
/// the engine's order inside each group (stable).
List<FeatureCheckModel> _problemsFirst(List<FeatureCheckModel> checks) {
  // Keep each check's original position so ties keep the engine's order.
  final indexed = checks.indexed.toList()
    ..sort((a, b) {
      final byStatus = _statusRank(a.$2.status).compareTo(_statusRank(b.$2.status));
      return byStatus != 0 ? byStatus : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Plain-language answer at the top: what happened, why, and what to do.
/// Written in English only.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final VerificationResultModel result;

  @override
  Widget build(BuildContext context) {
    final v = result.verdict;
    final color = v.color;
    // One line per failed or unclear check, as "Title: summary".
    final problems = [
      for (final c in result.checks)
        if (c.status == CheckStatus.fail || c.status == CheckStatus.inconclusive)
          '${c.title}: ${c.summary}',
    ];

    // Headline text for each verdict.
    final headline = switch (v) {
      VerificationVerdict.real =>
        'The note passed all of the app\'s checks. It looks REAL.',
      VerificationVerdict.fake =>
        'This note is FAKE. See the items marked FAIL below.',
      VerificationVerdict.unableToVerify || VerificationVerdict.incomplete =>
        'We could not verify this note. This does not mean it is fake.',
      VerificationVerdict.notBanknote => 'This does not look like a banknote.',
    };

    // Real and fake are the "decided" outcomes.
    final conclusive =
        v == VerificationVerdict.real || v == VerificationVerdict.fake;
    // Advice line, only for the cases where the user should retake photos.
    final action = switch (v) {
      VerificationVerdict.unableToVerify ||
      VerificationVerdict.incomplete =>
        'Retake clear photos of both sides: note flat, even light, no glare.',
      VerificationVerdict.notBanknote =>
        'Photograph the whole note on a plain dark surface.',
      _ => null,
    };

    // Card tinted with the verdict colour (low alpha = soft tint).
    return GlassContainer(
      glowColor: color,
      glowIntensity: 0.18,
      borderColor: color.withValues(alpha: 0.45),
      fill: color.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          Text(
            headline,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          // "X of Y checks passed"
          if (conclusive && result.applicableCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${result.passedCount} of ${result.applicableCount} checks passed',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
          ],
          // Up to 4 problems; the rest are left to the checklist below
          if (problems.isNotEmpty && v != VerificationVerdict.notBanknote) ...[
            const SizedBox(height: 10),
            for (final p in problems.take(4)) _Bullet(text: p),
            if (problems.length > 4)
              Text(
                '+${problems.length - 4} more in the checklist below',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
          ],
          // What to do next (retake advice)
          if (action != null) ...[
            const SizedBox(height: 10),
            Text(
              action,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
          // Disclaimer shown with a "real" result
          if (v == VerificationVerdict.real) ...[
            const SizedBox(height: 10),
            const Text(
              'This is an automated screening result, not a certified '
              'authentication.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cyan notice listing checks that did not run, so a score is never read
/// as covering features that were not inspected.
class _PartialBanner extends StatelessWidget {
  const _PartialBanner({required this.skipped});

  /// The checks whose status is "skipped".
  final List<FeatureCheckModel> skipped;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderColor: AppColors.cyan.withValues(alpha: 0.35),
      fill: AppColors.cyan.withValues(alpha: 0.06),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PARTIAL VERIFICATION',
                  style: TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Not checked: ${skipped.map((c) => c.title).join(', ')}. '
                  'The score covers only the checks that ran.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
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

/// Red banner for a "fake" verdict. Used for a photocopy or printout, and
/// for a back side that shows the wrong monument.
class _FakeBanner extends StatelessWidget {
  const _FakeBanner({required this.english});

  /// The reason, in English.
  final String english;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      glowColor: AppColors.crimson,
      glowIntensity: 0.4,
      borderColor: AppColors.crimson.withValues(alpha: 0.7),
      fill: AppColors.crimson.withValues(alpha: 0.14),
      child: Row(
        children: [
          const Icon(Icons.gpp_bad_rounded, color: AppColors.crimson, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fake Note',
                  style: TextStyle(
                    color: AppColors.crimson,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  english,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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

/// Explains why the score was lowered: shows the raw score and the final
/// percentage after the penalty. Red for a critical failure, amber for an
/// ordinary feature failure.
class _PenaltyBanner extends StatelessWidget {
  const _PenaltyBanner({required this.score});

  /// The confidence score that carries the penalty and its reason.
  final ConfidenceScoreModel score;

  @override
  Widget build(BuildContext context) {
    final critical = score.penalty == PenaltyType.criticalFailure;
    final color = critical ? AppColors.crimson : AppColors.amber;
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderColor: color.withValues(alpha: 0.4),
      fill: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            critical ? Icons.gpp_bad_outlined : Icons.trending_down_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  critical
                      ? 'CRITICAL FAILURE PENALTY'
                      : 'FEATURE FAILURE PENALTY',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${score.penaltyReason}. Raw ${score.rawScore.toStringAsFixed(1)}% '
                  'reduced to ${score.percentage}%.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
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

/// Amber panel for results the app could not decide. Says whether both
/// sides are needed or the photo should be retaken, lists the messages,
/// shows blur and glare bars, and gives photo tips.
class _InconclusivePanel extends StatelessWidget {
  const _InconclusivePanel({required this.result});

  final VerificationResultModel result;

  @override
  Widget build(BuildContext context) {
    final a = result.analysis;
    // "Incomplete" = a side is missing; otherwise the photo needs a retake.
    final incomplete = result.verdict == VerificationVerdict.incomplete;
    return GlassContainer(
      glowColor: AppColors.amber,
      glowIntensity: 0.2,
      borderColor: AppColors.amber.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                incomplete ? Icons.flip_rounded : Icons.camera_enhance_outlined,
                color: AppColors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  incomplete ? 'BOTH SIDES REQUIRED' : 'PLEASE RETAKE PHOTO',
                  style: const TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final m in result.messages) _Bullet(text: m),
          // Photo quality bars, only when both sides were analysed
          if (a?.front != null && a?.back != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _QualityMeter(side: 'FRONT', q: a!.front!.quality),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QualityMeter(side: 'BACK', q: a.back!.quality),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'Tips: place the note flat, avoid direct light reflections, hold the '
            'phone parallel to the note and keep it steady.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Two small bars (blur and glare) for one side of the note.
/// A bar turns red when its value is above the allowed maximum.
class _QualityMeter extends StatelessWidget {
  const _QualityMeter({required this.side, required this.q});

  /// "FRONT" or "BACK".
  final String side;

  /// Measured image quality for this side.
  final ImageQualityModel q;

  @override
  Widget build(BuildContext context) {
    // Draws one labelled bar. [v] is 0 to 1; [bad] makes it red.
    Widget bar(String label, double v, bool bad) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${(v * 100).round()}%',
            style: TextStyle(
              fontSize: 11,
              color: bad ? AppColors.crimson : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 4,
              color: bad ? AppColors.crimson : AppColors.emerald,
              backgroundColor: Colors.white10,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(side, style: Theme.of(context).textTheme.labelSmall),
        bar('Blur', q.blurScore, q.blurScore > ImageQualityModel.maxBlur),
        bar('Glare', q.glareScore, q.glareScore > ImageQualityModel.maxGlare),
      ],
    );
  }
}

/// Section title with a small cyan bar on the left and an optional
/// text on the right (for example "5/7 PASSED").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;

  /// Optional text shown at the right end of the row.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: AppColors.cyan),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppColors.cyan,
            ),
          ),
      ],
    );
  }
}

/// One line of text with a small cyan dot in front (a bullet point).
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.cyan),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides each checklist tile in with a small stagger: it fades in and
/// moves up 24 px. A higher [index] takes 90 ms longer, so tiles appear one
/// after another.
class _StaggeredIn extends StatelessWidget {
  const _StaggeredIn({required this.index, required this.child});

  /// Position of the tile in the checklist (0 = first).
  final int index;

  /// The tile to animate.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 500 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Fixed bar at the bottom of the screen holding one big button. The
/// background fades from clear to dark so the list scrolls under it neatly.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  /// Button text.
  final String label;

  /// Button colour.
  final Color color;

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Extra bottom space so the button clears the phone's bottom edge
      // (gesture bar).
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.onyx.withValues(alpha: 0), AppColors.onyxDeep],
        ),
      ),
      child: NeonButton(
        label: label,
        icon: Icons.document_scanner_outlined,
        color: color,
        onPressed: onPressed,
      ),
    );
  }
}

/// Offers a close-up photo of the note border so OCR can read the edge
/// microprint that is too small in the full scan.
class _MicroprintCloseUpCard extends ConsumerStatefulWidget {
  const _MicroprintCloseUpCard({
    required this.denomination,
    required this.summary,
  });

  /// Note value in rupees; the camera screen uses it as the text to read.
  final int denomination;

  /// Text of the microprint check, shown on the card.
  final String summary;

  @override
  ConsumerState<_MicroprintCloseUpCard> createState() =>
      _MicroprintCloseUpCardState();
}

/// State for the close-up card: runs the camera and checking steps.
class _MicroprintCloseUpCardState
    extends ConsumerState<_MicroprintCloseUpCard> {
  /// True while the close-up is being checked (shows a spinner).
  bool _busy = false;

  /// Guided close-up camera → sharpness check → OCR of the guide band.
  Future<void> _capture() async {
    while (true) {
      if (!mounted) return;
      final path = await Navigator.of(context).push<String>(
        CyberRoute(
          builder: (_) => MicroprintCameraScreen(
            expectedText: '${widget.denomination}',
          ),
        ),
      );
      if (path == null || !mounted) return;

      setState(() => _busy = true);
      final dir = await Directory.systemTemp.createTemp('mp_');
      final q = await ImagePreprocessor.analyzeCloseUp(path, dir.path);
      debugPrint('Close-up sharpness ${q.sharpness.toStringAsFixed(1)}');
      if (!mounted) return;

      // Too blurry: ask the user to retake or use the photo anyway.
      if (q.sharpness < ImagePreprocessor.closeUpSharpVariance) {
        setState(() => _busy = false);
        final retake = await showDialog<bool>(
          context: context,
          builder: (context) => const _BlurryCloseUpDialog(),
        );
        if (retake ?? true) continue; // open the camera again
        setState(() => _busy = true);
      }

      try {
        // Send the cropped band and the full close-up to the controller;
        // the results screen then updates with the new result.
        await ref
            .read(verificationControllerProvider.notifier)
            .applyMicroprintCloseUp([q.bandPath, path]);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderColor: AppColors.cyan.withValues(alpha: 0.35),
      fill: AppColors.cyan.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card title
          const Row(
            children: [
              Icon(Icons.zoom_in_rounded, color: AppColors.cyan),
              SizedBox(width: 10),
              Text(
                'EDGE MICROPRINT',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.summary,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          // Spinner while checking, otherwise the button to open the camera
          _busy
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  ),
                )
              : GhostButton(
                  label: 'Check microprint close-up',
                  icon: Icons.photo_camera_outlined,
                  color: AppColors.cyan,
                  onPressed: _capture,
                ),
        ],
      ),
    );
  }
}

/// Dialog shown when the close-up is not sharp enough to read the
/// microprint. Pops true for "retake" and false for "use anyway".
class _BlurryCloseUpDialog extends StatelessWidget {
  const _BlurryCloseUpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassContainer(
        borderRadius: 24,
        glowColor: AppColors.amber,
        borderColor: AppColors.amber.withValues(alpha: 0.5),
        fill: AppColors.surface.withValues(alpha: 0.95),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.blur_on_rounded, color: AppColors.amber, size: 44),
            const SizedBox(height: 12),
            const Text(
              'The photo is not in focus. Move a little closer, hold the '
              'phone steady and use good light.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The photo is not sharp. Move a little closer, hold the phone '
              'steady and use good light.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            NeonButton(
              label: 'DOBARA LEIN · RETAKE',
              icon: Icons.camera_alt_rounded,
              color: AppColors.amber,
              pulse: false,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Use anyway'),
            ),
          ],
        ),
      ),
    );
  }
}
