import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_models.dart';

/// Captured side rendered as a holographic card with a moving sheen and a
/// retake button.
class HoloPreviewCard extends StatefulWidget {
  const HoloPreviewCard({
    super.key,
    required this.side,
    required this.image,
    required this.onRetake,
  });

  final NoteSide side;
  final CapturedImage? image;
  final VoidCallback onRetake;

  @override
  State<HoloPreviewCard> createState() => _HoloPreviewCardState();
}

class _HoloPreviewCardState extends State<HoloPreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.side == NoteSide.front ? AppColors.cyan : AppColors.violet;
    final image = widget.image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: image != null ? AppColors.emerald : AppColors.amber,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.side.label,
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
              ),
            ),
            const Spacer(),
            if (image != null)
              Text(
                switch (image.source) {
                  CaptureSource.documentScanner => 'ML KIT',
                  CaptureSource.camera => 'CAMERA',
                  CaptureSource.gallery => 'GALLERY',
                },
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.8,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 22,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null)
                    Image.file(
                      File(image.path),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const _Missing(),
                    )
                  else
                    const _Missing(),
                  // Holographic sheen.
                  AnimatedBuilder(
                    animation: _sheen,
                    builder: (context, _) {
                      final x = -1.5 + 3 * _sheen.value;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(x - 0.6, -1),
                            end: Alignment(x + 0.6, 1),
                            colors: [
                              Colors.transparent,
                              accent.withValues(alpha: 0.10),
                              Colors.white.withValues(alpha: 0.22),
                              AppColors.violet.withValues(alpha: 0.10),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: AppColors.onyx.withValues(alpha: 0.7),
                      shape: const CircleBorder(
                        side: BorderSide(color: AppColors.glassBorder),
                      ),
                      child: IconButton(
                        tooltip: 'Retake ${widget.side.label}',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.refresh_rounded,
                            color: AppColors.textPrimary),
                        onPressed: widget.onRetake,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Icon(Icons.image_not_supported_outlined,
            color: AppColors.textMuted),
      ),
    );
  }
}
