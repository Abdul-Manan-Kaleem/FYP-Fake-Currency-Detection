import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/page_transitions.dart';
import '../../../../core/widgets/cyber_background.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../verification/presentation/screens/analyzing_screen.dart';
import '../../domain/capture_models.dart';
import '../controllers/capture_controller.dart';
import '../widgets/flip_prompt.dart';
import '../widgets/holo_preview_card.dart';
import '../widgets/scanner_hud.dart';
import '../widgets/step_indicator.dart';

/// Guided two-sided capture: FRONT → flip → BACK → dual preview staging.
class CaptureScreen extends ConsumerWidget {
  const CaptureScreen({super.key});

  void _analyze(BuildContext context, CaptureState s) {
    Navigator.of(context).push(
      CyberRoute(builder: (_) => AnalyzingScreen(front: s.front, back: s.back)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(captureControllerProvider.select((s) => s.sideError),
        (_, sideError) {
      if (sideError == null) return;
      ref.read(captureControllerProvider.notifier).clearError();
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (context) => _SideErrorDialog(error: sideError),
      );
    });

    ref.listen(captureControllerProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      final notifier = ref.read(captureControllerProvider.notifier);
      final side = ref.read(captureControllerProvider).basicCameraSide;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        duration: Duration(seconds: side == null ? 4 : 10),
        action: side == null
            ? null
            : SnackBarAction(
                label: 'USE BASIC CAMERA',
                onPressed: () => notifier.capture(side, basicCamera: true),
              ),
      ));
      notifier.clearError();
    });

    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);

    final Widget body = switch (state.step) {
      CaptureStep.front || CaptureStep.back => _CaptureStepView(
          key: ValueKey(state.step),
          side: state.step == CaptureStep.front ? NoteSide.front : NoteSide.back,
          busy: state.busy,
          busyMessage: state.busyMessage,
          onScan: (side) => controller.capture(side),
          onGallery: (side) => controller.capture(side, fromGallery: true),
          onSkipBack: state.step == CaptureStep.back
              ? () => _analyze(context, state)
              : null,
          onBackToFront: state.step == CaptureStep.back
              ? () => controller.goToStep(
                    state.front == null ? CaptureStep.front : CaptureStep.flip,
                  )
              : null,
        ),
      CaptureStep.flip => _FlipStepView(
          key: const ValueKey(CaptureStep.flip),
          front: state.front,
          onContinue: () {
            controller.confirmFlip();
            controller.capture(NoteSide.back);
          },
          onContinueGallery: () {
            controller.confirmFlip();
            controller.capture(NoteSide.back, fromGallery: true);
          },
        ),
      CaptureStep.review => _ReviewStepView(
          key: const ValueKey(CaptureStep.review),
          state: state,
          onRetake: (side) => _showRetakeSheet(context, ref, side),
          onAnalyze: () => _analyze(context, state),
        ),
    };

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('FAKE CURRENCY DETECTOR'),
        leading: state.step == CaptureStep.front
            ? null
            : IconButton(
                tooltip: 'Start over',
                icon: const Icon(Icons.restart_alt_rounded),
                onPressed: controller.reset,
              ),
      ),
      body: CyberBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              children: [
                StepIndicator(state: state),
                const SizedBox(height: 20),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRetakeSheet(
    BuildContext context,
    WidgetRef ref,
    NoteSide side,
  ) async {
    final controller = ref.read(captureControllerProvider.notifier);
    final fromGallery = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassContainer(
          fill: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: 24,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'RETAKE ${side.label}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 14),
                NeonButton(
                  label: 'SCAN WITH CAMERA',
                  icon: Icons.document_scanner_outlined,
                  pulse: false,
                  onPressed: () => Navigator.pop(context, false),
                ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'Upload from gallery',
                  icon: Icons.photo_library_outlined,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (fromGallery == null) return;
    await controller.capture(side, fromGallery: fromGallery);
  }
}

// -----------------------------------------------------------------------------

class _CaptureStepView extends StatelessWidget {
  const _CaptureStepView({
    super.key,
    required this.side,
    required this.busy,
    this.busyMessage,
    required this.onScan,
    required this.onGallery,
    this.onSkipBack,
    this.onBackToFront,
  });

  final NoteSide side;
  final bool busy;
  final String? busyMessage;
  final ValueChanged<NoteSide> onScan;
  final ValueChanged<NoteSide> onGallery;
  final VoidCallback? onSkipBack;
  final VoidCallback? onBackToFront;

  @override
  Widget build(BuildContext context) {
    final isFront = side == NoteSide.front;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InstructionHud(
            stepLabel: 'STEP ${isFront ? 1 : 2} / 2',
            text: 'Align ${side.label} of Pakistani Note within frame',
            hint: 'Place the note flat on a contrasting surface in good light. '
                'Edges are detected automatically and the background is '
                'cropped away.',
          ),
          const SizedBox(height: 22),
          ScannerHud(side: side, busy: busy, onTap: () => onScan(side)),
          if (busy && busyMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              busyMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.cyan, fontSize: 13),
            ),
          ],
          const SizedBox(height: 26),
          NeonButton(
            label: 'SCAN ${side.label}',
            icon: Icons.document_scanner_outlined,
            onPressed: busy ? null : () => onScan(side),
          ),
          const SizedBox(height: 12),
          GhostButton(
            label: 'Upload from gallery',
            icon: Icons.photo_library_outlined,
            onPressed: busy ? null : () => onGallery(side),
          ),
          if (onBackToFront != null || onSkipBack != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (onBackToFront != null)
                  TextButton.icon(
                    onPressed: busy ? null : onBackToFront,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary),
                  ),
                if (onSkipBack != null)
                  TextButton(
                    onPressed: busy ? null : onSkipBack,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted),
                    child: const Text('Analyze front only'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InstructionHud extends StatelessWidget {
  const _InstructionHud({
    required this.stepLabel,
    required this.text,
    required this.hint,
  });

  final String stepLabel;
  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      glowColor: AppColors.cyan,
      glowIntensity: 0.15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepLabel,
            style: const TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(hint, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FlipStepView extends StatelessWidget {
  const _FlipStepView({
    super.key,
    required this.front,
    required this.onContinue,
    required this.onContinueGallery,
  });

  final CapturedImage? front;
  final VoidCallback onContinue;
  final VoidCallback onContinueGallery;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
              const SizedBox(width: 8),
              Text(
                'FRONT CAPTURED',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.emerald,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FlipPrompt(front: front),
          ),
          const SizedBox(height: 36),
          Text(
            'Now flip the banknote to the BACK side',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 10),
          Text(
            'Both sides are mandatory. The back is checked for the matching '
            'denomination and 3 SBP seals.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          NeonButton(
            label: 'SCAN BACK',
            icon: Icons.flip_to_back_rounded,
            color: AppColors.violet,
            onPressed: onContinue,
          ),
          const SizedBox(height: 12),
          GhostButton(
            label: 'Upload back from gallery',
            icon: Icons.photo_library_outlined,
            onPressed: onContinueGallery,
          ),
        ],
      ),
    );
  }
}

class _ReviewStepView extends StatelessWidget {
  const _ReviewStepView({
    super.key,
    required this.state,
    required this.onRetake,
    required this.onAnalyze,
  });

  final CaptureState state;
  final ValueChanged<NoteSide> onRetake;
  final VoidCallback onAnalyze;

  static const _checks = [
    'Denomination',
    'Serial OCR',
    'SBP seals',
    'Lines / dots',
    'Thread',
    'Year',
    'MobileNetV3',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('DUAL PREVIEW', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text('Both sides staged',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: HoloPreviewCard(
                        side: NoteSide.front,
                        image: state.front,
                        onRetake: () => onRetake(NoteSide.front),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HoloPreviewCard(
                        side: NoteSide.back,
                        image: state.back,
                        onRetake: () => onRetake(NoteSide.back),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GlassContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PIPELINE',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in _checks)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.cyan.withValues(alpha: 0.3)),
                                color: AppColors.cyan.withValues(alpha: 0.06),
                              ),
                              child: Text(
                                c,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.cyan,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        NeonButton(
          label: 'ANALYZE BANKNOTE',
          icon: Icons.radar_rounded,
          color: AppColors.emerald,
          onPressed: state.isComplete && !state.busy ? onAnalyze : null,
        ),
      ],
    );
  }
}

/// Wrong side scanned: Urdu first, English below, one button.
class _SideErrorDialog extends StatelessWidget {
  const _SideErrorDialog({required this.error});

  final SideError error;

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
            const Icon(Icons.flip_rounded, color: AppColors.amber, size: 44),
            const SizedBox(height: 12),
            const Text(
              'GALAT SIDE · WRONG SIDE',
              style: TextStyle(
                color: AppColors.amber,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.urdu,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.english,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            NeonButton(
              label: 'THEEK HAI · OK',
              color: AppColors.amber,
              pulse: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
