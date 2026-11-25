/// "Not a note" dialog: a warning pop-up for images that cannot be checked.
///
/// Tells the user the photo is not a proper banknote image (invalid object,
/// paper/A4 page, or only part of a note) and offers "RETAKE SCAN".
/// Opened by showNotANoteDialog in analyzing_screen.dart.
/// Input: optional reasons, "what to do" steps, and a kind of rejection.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/neon_button.dart';
import '../../../../core/widgets/pulsing_glow.dart';

/// High-tech rejection modal shown when `isBanknote == false`.
///
/// Completes when the user taps "Retake Scan".
///
/// [reasons] are small grey lines of explanation. [steps] are advice lines
/// (the first is styled as a heading). [kind] is 'paper', 'partial' or null
/// and picks the wording. It cannot be dismissed by tapping outside.
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

/// The dialog content. Fields match [showNotANoteDialog].
class _NotANoteDialog extends StatelessWidget {
  const _NotANoteDialog({
    required this.reasons,
    required this.steps,
    required this.kind,
  });

  /// Extra explanation lines shown under the main text.
  final List<String> reasons;

  /// "What to do" lines, shown left-aligned.
  final List<String> steps;

  /// 'paper' (A4 / printout), 'partial' (half / cut-off note) or null.
  final String? kind;

  /// Heading text for this [kind].
  String get _title => switch (kind) {
    'paper' => 'NOT A PROPER IMAGE',
    'partial' => 'INCOMPLETE NOTE IMAGE',
    _ => 'INVALID OBJECT DETECTED',
  };

  /// Optional amber line under the heading (null for the default kind).
  String? get _subtitle => switch (kind) {
    'paper' => 'PAPER / A4 PAGE DETECTED',
    'partial' => 'HALF / PARTIAL NOTE DETECTED',
    _ => null,
  };

  /// Main explanation paragraph for this [kind].
  String get _body => switch (kind) {
    'paper' =>
      'You scanned a sheet of paper (an A4 page, printout or '
          'photocopy), not a real banknote. Paper images cannot be verified.',
    'partial' =>
      'Only part of the note is in the image. The app checks '
          'the whole note, so a half or cut-off note cannot be verified.',
    _ =>
      'The uploaded image is not of Pakistani currency.',
  };

  @override
  Widget build(BuildContext context) {
    // PopScope blocks the Android back button, so the user must tap Retake.
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
                // Red-tinted glass card (crimson at 10% blended over surface).
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
                        // Pulsing warning icon.
                        const PulsingGlow(
                          color: Color(0xFFFF5722),
                          size: 84,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 44,
                            color: Color(0xFFFF6E40),
                          ),
                        ),
                        // Heading.
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
                        // Optional subtitle.
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
                        // Main explanation.
                        Text(
                          _body,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        // Extra reason lines, if any.
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
                        // "What to do" box. The first line is styled as a heading.
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
                        // Button that closes the dialog so the user can rescan.
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
