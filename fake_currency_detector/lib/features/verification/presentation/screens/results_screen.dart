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
import '../widgets/verdict_badge.dart';
import '../widgets/verdict_style.dart';

/// Diagnostic dashboard: gauge, verdict, denomination and the per-feature
/// inspection checklist.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({
    super.key,
    required this.result,
    this.frontImagePath,
    this.backImagePath,
  });

  final VerificationResultModel result;

  /// Captured photos, used to draw YOLO's boxes on the results screen.
  final String? frontImagePath;
  final String? backImagePath;

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
    final microprintCheck = result.checks
        .where((c) => c.id == FeatureCheckId.microprint)
        .firstOrNull;
    final color = verdict.color;
    final inconclusive = !verdict.isConclusive;

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Center(
                  child: ConfidenceGauge(
                    percentage: result.confidence.percentage,
                    colors: verdict.gaugeColors,
                    caption: verdict.gaugeCaption,
                    accent: color,
                    inconclusive: inconclusive,
                  ),
                ),
                Center(child: VerdictBadge(verdict: verdict)),
                const SizedBox(height: 20),
                if (verdict == VerificationVerdict.fake) ...[
                  result.analysis?.rejectionKind == 'photocopy'
                      ? const _FakeBanner(
                          urdu: 'Ye photocopy lag rahi hai.',
                          english:
                              'This looks like a photocopy or printout on paper.',
                        )
                      : _FakeBanner(
                          urdu: 'Back side galat hai – Ye '
                              '${result.denomination ?? ''} ka asli note nahi lag raha.',
                          english: 'Backside monument mismatch: Rs '
                              '${result.denomination ?? ''} must show '
                              '${CurrencyRules.monuments[result.denomination] ?? 'its monument'}.',
                        ),
                  const SizedBox(height: 16),
                ],
                if (result.denomination != null)
                  _DenominationReadout(
                    value: result.denomination!,
                    color: color,
                  ),
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
                if (result.confidence.penalty != PenaltyType.none) ...[
                  const SizedBox(height: 16),
                  _PenaltyBanner(score: result.confidence),
                ],
                if (inconclusive) ...[
                  const SizedBox(height: 16),
                  _InconclusivePanel(result: result),
                ],
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
                if (result.checks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'INSPECTION CHECKLIST',
                    trailing:
                        '${result.passedCount}/${result.applicableCount} PASSED',
                  ),
                  const SizedBox(height: 10),
                  for (final (i, c) in result.checks.indexed)
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
                if (result.analysis?.detections.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  const _SectionHeader(title: 'WHAT YOLO11s SAW'),
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
                const SizedBox(height: 18),
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
        ),
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

/// Lists checks that did not run, so a score is never read as covering
/// features that were not inspected.
/// On-device stage latencies for performance logging (checklist item 18).
String _timings(VerificationResultModel r) {
  final t = r.analysis?.timingsMs ?? const {};
  if (t.isEmpty) return '';
  final parts = t.entries.map((e) => '${e.key} ${e.value} ms').join(' · ');
  return '\n$parts';
}

class _PartialBanner extends StatelessWidget {
  const _PartialBanner({required this.skipped});

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

/// Red, bilingual verdict for a photocopy / printout.
class _FakeBanner extends StatelessWidget {
  const _FakeBanner({required this.urdu, required this.english});

  final String urdu;
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
                  'Jaali Note / Fake Note',
                  style: TextStyle(
                    color: AppColors.crimson,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  urdu,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  english,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DenominationReadout extends StatelessWidget {
  const _DenominationReadout({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          formatRupees(value),
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: AppColors.textPrimary,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.5), blurRadius: 20),
            ],
          ),
        ),
        Text(
          'PAKISTANI RUPEES',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(letterSpacing: 4),
        ),
      ],
    );
  }
}

class _PenaltyBanner extends StatelessWidget {
  const _PenaltyBanner({required this.score});

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

class _InconclusivePanel extends StatelessWidget {
  const _InconclusivePanel({required this.result});

  final VerificationResultModel result;

  @override
  Widget build(BuildContext context) {
    final a = result.analysis;
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

class _QualityMeter extends StatelessWidget {
  const _QualityMeter({required this.side, required this.q});

  final String side;
  final ImageQualityModel q;

  @override
  Widget build(BuildContext context) {
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
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

/// Slides each checklist tile in with a small stagger.
class _StaggeredIn extends StatelessWidget {
  const _StaggeredIn({required this.index, required this.child});

  final int index;
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
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

  final int denomination;
  final String summary;

  @override
  ConsumerState<_MicroprintCloseUpCard> createState() =>
      _MicroprintCloseUpCardState();
}

class _MicroprintCloseUpCardState
    extends ConsumerState<_MicroprintCloseUpCard> {
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

/// Shown when the close-up is not sharp enough to read the microprint.
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
              'Focus clear nahi, thora qareeb layen aur mobile ko stable '
              'rakhen, roshni me rakhen.',
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
              child: const Text('Phir bhi istemal karen · Use anyway'),
            ),
          ],
        ),
      ),
    );
  }
}
