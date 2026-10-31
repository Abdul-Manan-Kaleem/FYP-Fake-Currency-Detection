import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_models.dart';

/// FRONT ─ BACK ─ ANALYZE progress rail.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.state});

  final CaptureState state;

  @override
  Widget build(BuildContext context) {
    final step = state.step;
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

class _Dot extends StatelessWidget {
  const _Dot({required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
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
