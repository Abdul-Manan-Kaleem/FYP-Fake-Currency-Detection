import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/laser_sweep.dart';
import '../../domain/capture_models.dart';

/// Viewfinder-style frame with corner brackets, laser sweep and a ghost
/// banknote outline. Tapping it launches the native scanner.
class ScannerHud extends StatelessWidget {
  const ScannerHud({
    super.key,
    required this.side,
    required this.onTap,
    this.busy = false,
  });

  final NoteSide side;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AspectRatio(
        aspectRatio: 1.8,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.black.withValues(alpha: 0.35),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: -8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: LaserSweep(
              active: !busy,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _NoteGhostPainter()),
                  const CustomPaint(painter: _BracketPainter()),
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: busy
                          ? const SizedBox.square(
                              dimension: 34,
                              child: CircularProgressIndicator(
                                color: AppColors.cyan,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  side == NoteSide.front
                                      ? Icons.document_scanner_outlined
                                      : Icons.flip_to_back_rounded,
                                  color: AppColors.cyan,
                                  size: 34,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'TAP TO SCAN ${side.label}',
                                  style: const TextStyle(
                                    color: AppColors.cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.4,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    top: 12,
                    child: _HudLabel(text: '${side.label} · AUTO-CROP'),
                  ),
                  const Positioned(
                    right: 14,
                    bottom: 12,
                    child: _HudLabel(text: 'WHOLE NOTE IN FRAME'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HudLabel extends StatelessWidget {
  const _HudLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.cyan.withValues(alpha: 0.7),
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.8,
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final len = size.shortestSide * 0.16;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    final path = Path()
      // top-left
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + len, r.top)
      // top-right
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + len)
      // bottom-right
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - len, r.bottom)
      // bottom-left
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - len);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = AppColors.cyan.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.cyan,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Faint dashed outline of a banknote to guide alignment.
class _NoteGhostPainter extends CustomPainter {
  const _NoteGhostPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTRB(28, 28, size.width - 28, size.height - 28),
      const Radius.circular(8),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.16);

    final path = Path()..addRRect(r);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }

    // Hint at the thread & watermark zones.
    final threadX = r.left + r.width * 0.62;
    canvas.drawLine(
      Offset(threadX, r.top + 4),
      Offset(threadX, r.bottom - 4),
      paint..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(r.left + r.width * 0.18, r.center.dy),
        width: r.height * 0.42,
        height: r.height * 0.55,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
