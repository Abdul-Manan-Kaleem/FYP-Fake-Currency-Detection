import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_models.dart';

/// FRONT ─ BACK ─ ANALYZE progress rail.
///
/// Shown at the top of the capture screen. Each step is a dot: green with
/// a tick when done, cyan when current, grey when still to come.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.state});

  /// Current capture state (which step, and which photos exist).
  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final step = state.step;
    // Each item is (label, done, active). The flip step counts as BACK.
    // ANALYZE is never "done" here; this screen is left when it starts.
    final items = [
      ('FRONT', state.front != null, step == CaptureStep.front),
      (
        'BACK',
        state.back != null,
        step == CaptureStep.back || step == CaptureStep.flip,
      ),
      ('ANALYZE', false, step == CaptureStep.review),
    ];

    return Row(
      children: [
        for (final (i, (label, done, active)) in items.indexed) ...[
          // Connector line before each dot except the first; green once
          // the previous step is done.
          if (i > 0)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: items[i - 1].$2
                      ? AppColors.emerald.withValues(alpha: 0.7)
                      : Colors.white10,
                ),
              ),
            ),
          _Dot(label: label, done: done, active: active),
        ],
      ],
    );
  }
}

/// One step marker: a round dot (with a tick when done) and its label.
class _Dot extends StatelessWidget {
  const _Dot({required this.label, required this.done, required this.active});

  final String label;

  /// Step finished: green with a tick.
  final bool done;

  /// Step in progress: cyan.
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Colour: green if done, cyan if active, otherwise muted grey.
    final color = done
        ? AppColors.emerald
        : active
            ? AppColors.cyan
            : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 1.5),
            boxShadow: active || done
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
                : null,
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 13, color: color)
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
            color: color,
          ),
        ),
      ],
    );
  }
}
