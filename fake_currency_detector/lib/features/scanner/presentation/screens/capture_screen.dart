import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/page_transitions.dart';
import '../../../../core/widgets/cyber_background.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../verification/presentation/screens/analyzing_screen.dart';
import '../../../verification/presentation/widgets/note_identity_banner.dart';
import '../../domain/capture_models.dart';
import '../controllers/capture_controller.dart';
import '../widgets/flip_prompt.dart';
import '../widgets/holo_preview_card.dart';
import '../widgets/scanner_hud.dart';
import '../widgets/step_indicator.dart';

/// Main capture screen of the app (the scanner part of the flow).
///
/// It guides the user through: scan FRONT -> flip note -> scan BACK ->
/// review both photos -> press Analyze (opens AnalyzingScreen).
/// The current step and the photos live in captureControllerProvider;
/// this screen only shows the right view for the current step.
class CaptureScreen extends ConsumerWidget {
  const CaptureScreen({super.key});

  /// Opens the analysis screen with the captured front and back photos.
  /// The back can be null when the user chose "Analyze front only".
  void _analyze(BuildContext context, CaptureState s) {
    Navigator.of(context).push(
      // The original photos are checked unless the user turned Enhance ON.
      CyberRoute(
          builder: (_) =>
              AnalyzingScreen(front: s.frontToUse, back: s.backToUse)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listener 1: wrong side / not a banknote -> show a pop-up dialog once,
    // then clear the error so it does not show again.
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

    // Listener 2: general capture error -> snackbar. If a side is waiting,
    // the snackbar offers "USE BASIC CAMERA" (and stays longer: 10s vs 4s).
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

    // Pick the view for the current step: front/back share one view,
    // then the flip prompt, then the final review.
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
          onEnhance: controller.setEnhance,
        ),
    };

    return Scaffold(
      extendBodyBehindAppBar: true,
      // Top bar: title, plus a "start over" button after the first step.
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
                // Progress dots at the top.
                StepIndicator(state: state),
                const SizedBox(height: 20),
                // Step content, with a fade + slide when the step changes.
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

  /// Bottom sheet asking how to retake one side: camera or gallery.
  /// Closing the sheet without choosing does nothing.
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

/// View for the FRONT or BACK scan step.
///
/// The user sees instructions, the scanner frame, a SCAN button and an
/// "Upload from gallery" button. On the back step there are also "Back"
/// and "Analyze front only" links. Buttons are disabled while [busy].
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

  /// Which side of the note this step is capturing.
  final NoteSide side;

  /// True while a photo is being captured or processed.
  final bool busy;

  /// Progress text shown under the frame while busy.
  final String? busyMessage;
  final ValueChanged<NoteSide> onScan;
  final ValueChanged<NoteSide> onGallery;

  /// Only set on the back step: skip the back and analyze the front alone.
  final VoidCallback? onSkipBack;

  /// Only set on the back step: go to the previous step.
  final VoidCallback? onBackToFront;

  @override
  Widget build(BuildContext context) {
    final isFront = side == NoteSide.front;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Instruction card (step number and what to do).
          _InstructionHud(
            stepLabel: 'STEP ${isFront ? 1 : 2} / 2',
            text: 'Align ${side.label} of Pakistani Note within frame',
            hint: 'Place the note flat on a contrasting surface in good light. '
                'Edges are detected automatically and the background is '
                'cropped away.',
          ),
          const SizedBox(height: 22),
          // Scanner frame (tapping it also starts a scan).
          ScannerHud(side: side, busy: busy, onTap: () => onScan(side)),
          // Progress message while busy.
          if (busy && busyMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              busyMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.cyan, fontSize: 13),
            ),
          ],
          const SizedBox(height: 26),
          // Main actions: scan with camera, or pick from gallery.
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
          // Navigation links (back step only).
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

/// Glowing card with the step label ("STEP 1 / 2"), a headline and a hint.
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

/// View shown after the front is accepted: asks the user to flip the note.
///
/// The user sees the detected denomination, an animated flip prompt, and
/// two buttons: scan the back with the camera, or upload it from gallery.
class _FlipStepView extends StatelessWidget {
  const _FlipStepView({
    super.key,
    required this.front,
    required this.onContinue,
    required this.onContinueGallery,
  });

  /// The accepted front photo (used for the preview and denomination).
  final CapturedImage? front;

  /// Scan the back with the camera.
  final VoidCallback onContinue;

  /// Pick the back from the gallery.
  final VoidCallback onContinueGallery;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          // "Front captured" confirmation.
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
          const SizedBox(height: 14),
          // The first photo was accepted as a banknote: say which value.
          NoteIdentityBanner(frontValue: front?.denomination, compact: true),
          const SizedBox(height: 18),
          // Animated card that flips from front to back.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FlipPrompt(front: front),
          ),
          const SizedBox(height: 36),
          // Instruction text.
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
          // Actions for the back side.
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

/// Final step: shows both photos side by side before analysis.
///
/// The user can retake either side (refresh button on its card) or press
/// "ANALYZE BANKNOTE". The button is off until both sides are captured
/// and nothing is busy.
class _ReviewStepView extends StatelessWidget {
  const _ReviewStepView({
    super.key,
    required this.state,
    required this.onRetake,
    required this.onAnalyze,
    required this.onEnhance,
  });

  final CaptureState state;
  final ValueChanged<NoteSide> onRetake;
  final VoidCallback onAnalyze;

  /// Called when the user flips the manual Enhance switch.
  final ValueChanged<bool> onEnhance;

  /// Names of the checks shown as chips under "PIPELINE". Display only;
  /// the real checks run later on the analyzing screen.
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
                // Front and back preview cards, side by side.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: HoloPreviewCard(
                        side: NoteSide.front,
                        image: state.frontToUse,
                        onRetake: () => onRetake(NoteSide.front),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HoloPreviewCard(
                        side: NoteSide.back,
                        image: state.backToUse,
                        onRetake: () => onRetake(NoteSide.back),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Manual Enhance switch. OFF (default) = the original photos
                // are checked; ON = the enhanced copies are checked.
                GlassContainer(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enhance photos'),
                    subtitle: Text(
                      state.enhance
                          ? 'ON: the enhanced photos are checked'
                          : 'OFF: the original photos are checked',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    value: state.enhance,
                    onChanged: state.isComplete && !state.busy ? onEnhance : null,
                  ),
                ),
                const SizedBox(height: 24),
                // Card listing the checks that will run.
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
        // Pinned at the bottom; starts the analysis.
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

/// Pop-up shown when the scanned photo is rejected (wrong side, or not a
/// banknote). English message and one OK button.
/// Red is used when it is not a banknote, amber for a wrong side.
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
        glowColor: error.notBanknote ? AppColors.crimson : AppColors.amber,
        borderColor: (error.notBanknote ? AppColors.crimson : AppColors.amber)
            .withValues(alpha: 0.5),
        fill: AppColors.surface.withValues(alpha: 0.95),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error.notBanknote
                  ? Icons.do_not_disturb_alt_rounded
                  : Icons.flip_rounded,
              color: error.notBanknote ? AppColors.crimson : AppColors.amber,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              error.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: error.notBanknote ? AppColors.crimson : AppColors.amber,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.english,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            NeonButton(
              label: 'OK',
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
