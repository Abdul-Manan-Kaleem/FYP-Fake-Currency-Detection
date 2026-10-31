import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/pulsing_glow.dart';

/// High-tech rejection modal shown when `isBanknote == false`.
///
/// Completes when the user taps "Retake Scan".
Future<void> showNotANoteDialog(
  BuildContext context, {
  List<String> reasons = const [],
  List<String> steps = const [],
  String? kind,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Invalid object',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, _, _) =>
        _NotANoteDialog(reasons: reasons, steps: steps, kind: kind),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NotANoteDialog extends StatelessWidget {
  const _NotANoteDialog({
    required this.reasons,
    required this.steps,
    required this.kind,
  });

  final List<String> reasons;

  /// "What to do" lines, shown left-aligned.
  final List<String> steps;

  /// 'paper' (A4 / printout), 'partial' (half / cut-off note) or null.
  final String? kind;

  String get _title => switch (kind) {
    'paper' => 'NOT A PROPER IMAGE',
    'partial' => 'INCOMPLETE NOTE IMAGE',
    _ => 'INVALID OBJECT DETECTED',
  };

  String? get _subtitle => switch (kind) {
    'paper' => 'PAPER / A4 PAGE DETECTED',
    'partial' => 'HALF / PARTIAL NOTE DETECTED',
    _ => null,
  };

  String get _body => switch (kind) {
    'paper' =>
      'You scanned a sheet of paper (an A4 page, printout or '
          'photocopy), not a real banknote. Paper images cannot be verified.',
    'partial' =>
      'Only part of the note is in the image. The app checks '
          'the whole note, so a half or cut-off note cannot be verified.',
    _ =>
      'The captured image is not recognized as a Pakistani currency '
          'note. Please ensure the note is placed on a flat surface with '
          'sufficient lighting and try again.',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: Colors.transparent,
                child: GlassContainer(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  borderRadius: 28,
                  glowColor: AppColors.crimson,
                  glowIntensity: 0.45,
                  borderColor: AppColors.crimson.withValues(alpha: 0.45),
                  fill: Color.alphaBlend(
                    AppColors.crimson.withValues(alpha: 0.10),
                    AppColors.surface,
                  ).withValues(alpha: 0.94),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PulsingGlow(
                          color: Color(0xFFFF5722),
                          size: 84,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 44,
                            color: Color(0xFFFF6E40),
                          ),
                        ),
                        Text(
                          _title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.crimson,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.4,
                            fontSize: 18,
                          ),
                        ),
                        if (_subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _subtitle!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.amber,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.6,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          _body,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (reasons.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          for (final r in reasons)
                            Text(
                              r,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                        if (steps.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.04),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final (i, step) in steps.indexed)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      step,
                                      style: TextStyle(
                                        fontSize: i == 0 ? 12 : 12.5,
                                        fontWeight: i == 0
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: i == 0
                                            ? AppColors.cyan
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        NeonButton(
                          label: 'RETAKE SCAN',
                          icon: Icons.document_scanner_outlined,
                          color: AppColors.crimson,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
