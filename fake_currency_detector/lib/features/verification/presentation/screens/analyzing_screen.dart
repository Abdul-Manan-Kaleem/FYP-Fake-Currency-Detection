import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/page_transitions.dart';
import '../../../../core/widgets/cyber_background.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/laser_sweep.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../scanner/domain/capture_models.dart';
import '../../../scanner/presentation/controllers/capture_controller.dart';
import '../../data/on_device/page_detector.dart';
import '../../data/on_device/partial_note_detector.dart';
import '../../domain/note_image_input.dart';
import '../controllers/verification_controller.dart';
import '../widgets/not_a_note_dialog.dart';
import '../widgets/radar_scanner.dart';
import 'results_screen.dart';

/// "Analyzing" screen. It sits between the capture screens and the results.
///
/// Flow: the user photographs the FRONT and BACK of the note, then this
/// screen opens and starts the on-device check (verificationController).
///
/// What it shows, from top to bottom:
///  1. Title "ANALYZING BANKNOTE".
///  2. A small chip naming the on-device tools used.
///  3. A radar animation with a status line that changes every 700 ms.
///  4. Thumbnails of the front and back photos with a laser sweep.
///  5. A thin progress bar at the bottom.
///
/// When the check ends, the screen reacts to the controller status:
///  - completed: replaces itself with the ResultsScreen.
///  - rejected: shows the "not a banknote" dialog, then reopens the camera.
///  - failed: shows an error panel with RETRY and "Back to capture".
class AnalyzingScreen extends ConsumerStatefulWidget {
  /// The two photos taken by the user. Either can be null if missing.
  const AnalyzingScreen({super.key, this.front, this.back});

  /// Photo of the front side of the note.
  final CapturedImage? front;

  /// Photo of the back side of the note.
  final CapturedImage? back;

  @override
  ConsumerState<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

/// State for [AnalyzingScreen]: runs the status-text timer and starts the
/// verification once the first frame is drawn.
class _AnalyzingScreenState extends ConsumerState<AnalyzingScreen> {
  /// Status lines shown one after another (English).
  /// They are only a visual cue. They are not tied to real progress.
  static const _stages = [
    'Step 1: Checking front side…',
    'Step 2: Checking back side…',
    'Checking security features: seals, thread, lines/dots…',
    'Reading serial numbers…',
    'Preparing result…',
  ];

  /// Timer that moves to the next status line.
  Timer? _ticker;

  /// Index of the status line currently shown.
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    // Every 700 ms show the next status line (wraps back to the first).
    _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (mounted) setState(() => _stage = (_stage + 1) % _stages.length);
    });
    // Start the check after the first frame, so the screen is already visible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// Turns a captured photo into the input object the checker needs.
  /// Returns null when that side was not captured.
  static NoteImageInput? _input(CapturedImage? image) => image == null
      ? null
      : NoteImageInput(path: image.path);

  /// Starts the on-device check. Also used by the RETRY button.
  void _start() {
    ref.read(verificationControllerProvider.notifier).verify(
          front: _input(widget.front),
          back: _input(widget.back),
        );
  }

  // Stop the timer when the screen closes.
  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Called when the image was rejected (for example "not a banknote").
  /// Shows a dialog, clears the old state, goes back and reopens the camera
  /// for a new FRONT photo.
  Future<void> _onRejected(List<String> messages, String? kind) async {
    // First message repeats the dialog body; the rest are the gate's reasons
    // plus, for paper, the "What to do" steps.
    final rest = messages.skip(1).toList();
    final steps = [
      ...PageDetector.guidance,
      ...PartialNoteDetector.guidance,
    ];
    await showNotANoteDialog(
      context,
      kind: kind,
      reasons: [for (final m in rest) if (!steps.contains(m)) m],
      steps: [for (final m in rest) if (steps.contains(m)) m],
    );
    if (!mounted) return;
    final capture = ref.read(captureControllerProvider.notifier);
    ref.read(verificationControllerProvider.notifier).reset();
    capture.reset();
    Navigator.of(context).pop();
    // Reopen the scanner straight away for a fresh FRONT capture.
    unawaited(capture.capture(NoteSide.front));
  }

  @override
  Widget build(BuildContext context) {
    // Watch the controller status and navigate when the check finishes.
    ref.listen(verificationControllerProvider, (prev, next) {
      if (prev?.status == next.status) return;
      switch (next.status) {
        case VerificationStatus.completed:
          _ticker?.cancel();
          Navigator.of(context).pushReplacement(
            CyberRoute(
              builder: (_) => ResultsScreen(
                result: next.result!,
                frontImagePath: widget.front?.path,
                backImagePath: widget.back?.path,
              ),
            ),
          );
        case VerificationStatus.rejected:
          _ticker?.cancel();
          _onRejected(
            next.result?.messages ?? const [],
            next.result?.analysis?.rejectionKind,
          );
        default:
          break;
      }
    });

    final state = ref.watch(verificationControllerProvider);
    final failed = state.status == VerificationStatus.failed;

    return Scaffold(
      body: CyberBackground(
        // Red glow on error, cyan while working.
        accent: failed ? AppColors.crimson : AppColors.cyan,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            // Error panel if the check failed, otherwise the progress view.
            child: failed
                ? _ErrorPanel(
                    title: state.error!.title,
                    message: state.error!.message,
                    onRetry: _start,
                    onBack: () {
                      ref.read(verificationControllerProvider.notifier).reset();
                      Navigator.of(context).pop();
                    },
                  )
                : Column(
                    children: [
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        'ANALYZING BANKNOTE',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      // Chip naming the tools used (all run on the phone)
                      _EngineChip(
                        label: 'ON-DEVICE · YOLO11s + ML Kit OCR + CNN classifiers',
                      ),
                      const Spacer(),
                      // Radar animation in the middle
                      const RadarScanner(size: 230),
                      const SizedBox(height: 28),
                      // Status line, fades between texts (key = stage index)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _stages[_stage],
                          key: ValueKey(_stage),
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Front and back photo thumbnails side by side
                      Row(
                        children: [
                          Expanded(child: _Thumb(image: widget.front, label: 'FRONT')),
                          const SizedBox(width: 12),
                          Expanded(child: _Thumb(image: widget.back, label: 'BACK')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Thin endless progress bar at the bottom
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          color: AppColors.cyan,
                          backgroundColor: AppColors.glassFill,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded chip under the title that shows the text in [label].
class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.label});

  /// Text shown inside the chip (kept to one line, cut with "..." if long).
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
        color: AppColors.glassFill,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}

/// Small preview of one captured photo with a moving laser line and a
/// FRONT / BACK label. Shows a plain dark box if the photo is missing.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.label});

  /// The photo to preview (null if that side was not captured).
  final CapturedImage? image;

  /// Label drawn in the top-left corner.
  final String label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LaserSweep(
          duration: const Duration(milliseconds: 1500),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image.file(File(image!.path), fit: BoxFit.cover)
              else
                const ColoredBox(color: AppColors.surface),
              // Light dark tint so the label stays readable on the photo
              Container(color: AppColors.onyx.withValues(alpha: 0.35)),
              Positioned(
                left: 8,
                top: 6,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                    color: AppColors.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red card shown when the check failed (see VerificationStatus.failed).
/// Offers RETRY and a way back to the capture screen.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  /// Short error heading.
  final String title;

  /// Longer explanation of what went wrong.
  final String message;

  /// Runs the check again.
  final VoidCallback onRetry;

  /// Clears the state and returns to the capture screen.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        glowColor: AppColors.crimson,
        borderColor: AppColors.crimson.withValues(alpha: 0.4),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.crimson, size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.crimson,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            NeonButton(
              label: 'RETRY',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GhostButton(
                label: 'Back to capture',
                icon: Icons.arrow_back_rounded,
                onPressed: onBack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
