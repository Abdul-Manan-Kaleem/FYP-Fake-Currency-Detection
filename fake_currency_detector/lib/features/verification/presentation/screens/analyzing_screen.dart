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

/// Processing state: radar sweep while the pipeline runs, then routes to the
/// results dashboard or the "not a banknote" alert.
class AnalyzingScreen extends ConsumerStatefulWidget {
  const AnalyzingScreen({super.key, this.front, this.back});

  final CapturedImage? front;
  final CapturedImage? back;

  @override
  ConsumerState<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends ConsumerState<AnalyzingScreen> {
  static const _stages = [
    'Step 1: Front side check ho raha hai… · Checking front side',
    'Step 2: Back side check ho raha hai… · Checking back side',
    'Security features dekhe ja rahe hain… · Seals, thread, lines/dots',
    'Serial number parha ja raha hai… · Reading serial numbers',
    'Result tayyar ho raha hai… · Preparing result',
  ];

  Timer? _ticker;
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (mounted) setState(() => _stage = (_stage + 1) % _stages.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  static NoteImageInput? _input(CapturedImage? image) => image == null
      ? null
      : NoteImageInput(path: image.path);

  void _start() {
    ref.read(verificationControllerProvider.notifier).verify(
          front: _input(widget.front),
          back: _input(widget.back),
        );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

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
        accent: failed ? AppColors.crimson : AppColors.cyan,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      Text(
                        'ANALYZING BANKNOTE',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      _EngineChip(
                        label: 'ON-DEVICE · YOLO11s + ML Kit OCR + Rs 5,000 CNN',
                      ),
                      const Spacer(),
                      const RadarScanner(size: 230),
                      const SizedBox(height: 28),
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
                      Row(
                        children: [
                          Expanded(child: _Thumb(image: widget.front, label: 'FRONT')),
                          const SizedBox(width: 12),
                          Expanded(child: _Thumb(image: widget.back, label: 'BACK')),
                        ],
                      ),
                      const SizedBox(height: 16),
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

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.label});

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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.label});

  final CapturedImage? image;
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

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
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
