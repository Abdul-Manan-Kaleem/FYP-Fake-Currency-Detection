import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../data/models/feature_check_model.dart';
import 'serial_comparison_view.dart';
import 'verdict_style.dart';

/// Expandable pass/fail row in the inspection checklist.
class InspectionTile extends StatefulWidget {
  const InspectionTile({
    super.key,
    required this.check,
    this.initiallyExpanded = false,
  });

  final FeatureCheckModel check;
  final bool initiallyExpanded;

  @override
  State<InspectionTile> createState() => _InspectionTileState();
}

class _InspectionTileState extends State<InspectionTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final color = c.status.color;

    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      borderColor: c.failed ? AppColors.crimson.withValues(alpha: 0.35) : null,
      glowColor: c.failed ? AppColors.crimson : null,
      glowIntensity: 0.18,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Haptics.tap();
            setState(() => _expanded = !_expanded);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusOrb(status: c.status),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(c.id.icon,
                                    size: 15, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    c.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                if (c.isCritical) ...[
                                  const SizedBox(width: 6),
                                  const _CoreTag(),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.summary,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            c.status.label,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c.earned.toStringAsFixed(1)}/${c.weight.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(Icons.expand_more_rounded,
                            color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.glassBorder),
                    const SizedBox(height: 12),
                    if (c.serialComparison != null) ...[
                      SerialComparisonView(comparison: c.serialComparison!),
                      const SizedBox(height: 12),
                    ],
                    for (final d in c.details) _DetailRow(detail: d),
                    if (c.details.isEmpty && c.serialComparison == null)
                      const Text(
                        'No additional detector output for this check.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.status});

  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12),
        ],
      ),
      child: Icon(status.icon, size: 18, color: color),
    );
  }
}

class _CoreTag extends StatelessWidget {
  const _CoreTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'CORE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: AppColors.cyan,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});

  final CheckDetailModel detail;

  @override
  Widget build(BuildContext context) {
    final ok = detail.ok;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok == null
                ? Icons.circle
                : ok
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
            size: ok == null ? 6 : 15,
            color: ok == null
                ? AppColors.textMuted
                : ok
                    ? AppColors.emerald
                    : AppColors.crimson,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail.label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          Text(
            detail.value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
