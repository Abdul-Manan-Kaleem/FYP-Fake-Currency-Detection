/// Detection overlay: the captured note photo with the detector's boxes.
///
/// Draws a coloured box and label for every YOLO detection on the photo,
/// and lists how many of each class were found (confirmed and low-confidence).
/// Used in results_screen.dart, once per side (front and back).
/// Input: side title, image file path, and the detections for that side.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../data/models/note_analysis_model.dart';
import '../../domain/currency_rules.dart';

/// Colour for a box, chosen by YOLO class id (see YoloClass).
///
/// Used for both the box outlines and the count chips.
Color detectionColor(int classId) => switch (classId) {
      <= 6 => AppColors.cyan, // note classes
      7 => Colors.white, // printed_year
      8 => AppColors.violet, // sbp_seal
      9 || 10 => const Color(0xFFFF4FD8), // dots, lines
      11 => AppColors.emerald, // security_thread
      12 => AppColors.amber, // serial_number
      _ => AppColors.textSecondary,
    };

/// Shortens a class label for display, e.g. "security_thread" becomes
/// "thread" and "serial_number" becomes "serial".
String _shortLabel(String label) => label
    .replaceAll('Rs Note', ' Rs')
    .replaceAll('security_', '')
    .replaceAll('_number', '')
    .replaceAll('printed_', '')
    .replaceAll('sbp_', '');

/// The captured side with every YOLO11s box drawn on top, plus a count of
/// confirmed and low-confidence boxes per class.
///
/// [side] is the title shown above the image. [imagePath] is the photo file
/// (null or missing shows a plain dark box). [detections] holds the boxes
/// and the image width and height.
class DetectionOverlayCard extends StatelessWidget {
  const DetectionOverlayCard({
    super.key,
    required this.side,
    required this.imagePath,
    required this.detections,
  });

  /// Title shown above the image (for example the side name).
  final String side;

  /// Path of the captured photo on the phone, or null.
  final String? imagePath;

  /// Boxes found on this side, plus the image size.
  final SideDetectionsModel detections;

  /// Boxes with a score at or above this are "confirmed"; lower ones are
  /// drawn fainter and counted as "low".
  static const double _confirm = CurrencyRules.minDetectionConfidence;

  @override
  Widget build(BuildContext context) {
    // Count boxes per class label: (class id, confirmed, uncertain).
    final counts = <String, (int, int, int)>{}; // label → (id, confirmed, uncertain)
    for (final b in detections.boxes) {
      final (id, c, u) = counts[b.label] ?? (b.classId, 0, 0);
      counts[b.label] =
          b.score >= _confirm ? (id, c + 1, u) : (id, c, u + 1);
    }
    // Sort the chips by class id so the order is stable.
    final entries = counts.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));

    // Card: title, image with boxes, then count chips.
    return GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(side, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          // Photo with the boxes painted on top. The aspect ratio matches the
          // image so box positions (stored as fractions) line up.
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
          // Count chips, or a message when nothing was detected.
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

/// Small rounded chip such as "serial ×1 (+1 low)".
///
/// [label] is the class name, [color] the class colour, [confirmed] the
/// number of confirmed boxes and [uncertain] the number of low-score boxes.
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

/// Draws every detection box and its label on top of the photo.
///
/// Box coordinates are fractions (0-1) of the image, so they are multiplied
/// by the canvas size here.
class _BoxPainter extends CustomPainter {
  _BoxPainter(this.boxes);

  final List<DetectionBoxModel> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    // Large boxes (the note itself) first so feature boxes stay on top.
    final ordered = [...boxes]
      ..sort((a, b) => ((b.right - b.left) * (b.bottom - b.top))
          .compareTo((a.right - a.left) * (a.bottom - a.top)));

    // Draw each box: outline, then a small label tab.
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

      // Outline: thicker and fully opaque when confirmed.
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = confirmed ? 2 : 1
          ..color = color,
      );

      // Label text, e.g. "thread 0.91" (short name + score).
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
      // Put the label above the box, or inside the top edge if no room.
      final labelTop = rect.top - tp.height - 2 >= 0 ? rect.top - tp.height - 2 : rect.top;
      final bg = Rect.fromLTWH(rect.left, labelTop, tp.width + 6, tp.height + 2);
      canvas.drawRect(bg, Paint()..color = color);
      tp.paint(canvas, Offset(bg.left + 3, bg.top + 1));
    }
  }

  // Repaint only when the list of boxes changes.
  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.boxes != boxes;
}
