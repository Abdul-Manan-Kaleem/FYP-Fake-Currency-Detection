import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../data/models/note_analysis_model.dart';
import '../../domain/currency_rules.dart';

/// Colour per YOLO class id (see YoloClass).
Color detectionColor(int classId) => switch (classId) {
      <= 6 => AppColors.cyan, // note classes
      7 => Colors.white, // printed_year
      8 => AppColors.violet, // sbp_seal
      9 || 10 => const Color(0xFFFF4FD8), // dots, lines
      11 => AppColors.emerald, // security_thread
      12 => AppColors.amber, // serial_number
      _ => AppColors.textSecondary,
    };

String _shortLabel(String label) => label
    .replaceAll('Rs Note', ' Rs')
    .replaceAll('security_', '')
    .replaceAll('_number', '')
    .replaceAll('printed_', '')
    .replaceAll('sbp_', '');

/// The captured side with every YOLO11s box drawn on top, plus a count of
/// confirmed and low-confidence boxes per class.
class DetectionOverlayCard extends StatelessWidget {
  const DetectionOverlayCard({
    super.key,
    required this.side,
    required this.imagePath,
    required this.detections,
  });

  final String side;
  final String? imagePath;
  final SideDetectionsModel detections;

  static const double _confirm = CurrencyRules.minDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    final counts = <String, (int, int, int)>{}; // label → (id, confirmed, uncertain)
    for (final b in detections.boxes) {
      final (id, c, u) = counts[b.label] ?? (b.classId, 0, 0);
      counts[b.label] =
          b.score >= _confirm ? (id, c + 1, u) : (id, c, u + 1);
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));

    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(side, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: detections.width / detections.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath != null && File(imagePath!).existsSync())
                    Image.file(File(imagePath!), fit: BoxFit.fill)
                  else
                    const ColoredBox(color: AppColors.surface),
                  CustomPaint(painter: _BoxPainter(detections.boxes)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Text('No detections',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in entries)
                  _CountChip(
                    label: _shortLabel(e.key),
                    color: detectionColor(e.value.$1),
                    confirmed: e.value.$2,
                    uncertain: e.value.$3,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.color,
    required this.confirmed,
    required this.uncertain,
  });

  final String label;
  final Color color;
  final int confirmed;
  final int uncertain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label ×$confirmed${uncertain > 0 ? ' (+$uncertain low)' : ''}',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes);

  final List<DetectionBoxModel> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    // Large boxes (the note itself) first so feature boxes stay on top.
    final ordered = [...boxes]
      ..sort((a, b) => ((b.right - b.left) * (b.bottom - b.top))
          .compareTo((a.right - a.left) * (a.bottom - a.top)));

    for (final b in ordered) {
      final confirmed = b.score >= CurrencyRules.minDetectionConfidence;
      final color = detectionColor(b.classId)
          .withValues(alpha: confirmed ? 1 : 0.55);
      final rect = Rect.fromLTRB(
        b.left * size.width,
        b.top * size.height,
        b.right * size.width,
        b.bottom * size.height,
      ).deflate(1);

      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = confirmed ? 2 : 1
          ..color = color,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${_shortLabel(b.label)} ${b.score.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: AppColors.onyx,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = rect.top - tp.height - 2 >= 0 ? rect.top - tp.height - 2 : rect.top;
      final bg = Rect.fromLTWH(rect.left, labelTop, tp.width + 6, tp.height + 2);
      canvas.drawRect(bg, Paint()..color = color);
      tp.paint(canvas, Offset(bg.left + 3, bg.top + 1));
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.boxes != boxes;
}
