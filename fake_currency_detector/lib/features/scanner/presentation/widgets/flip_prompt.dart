import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/capture_models.dart';

/// Animated 3D card flip that shows the captured FRONT turning over to an
/// empty BACK, prompting the user to flip the physical note.
class FlipPrompt extends StatefulWidget {
  const FlipPrompt({super.key, required this.front});

  final CapturedImage? front;

  @override
  State<FlipPrompt> createState() => _FlipPromptState();
}

class _FlipPromptState extends State<FlipPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Hold on front, flip, hold on back, flip back.
        final t = _c.value;
        final double turn;
        if (t < 0.3) {
          turn = 0;
        } else if (t < 0.5) {
          turn = Curves.easeInOutCubic.transform((t - 0.3) / 0.2);
        } else if (t < 0.8) {
          turn = 1;
        } else {
          turn = 1 - Curves.easeInOutCubic.transform((t - 0.8) / 0.2);
        }
        final angle = turn * math.pi;
        final showBack = angle > math.pi / 2;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
            child: AspectRatio(
              aspectRatio: 1.8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (showBack ? AppColors.violet : AppColors.cyan)
                        .withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (showBack ? AppColors.violet : AppColors.cyan)
                          .withValues(alpha: 0.3),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: showBack ? const _BackFace() : _FrontFace(widget.front),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FrontFace extends StatelessWidget {
  const _FrontFace(this.image);

  final CapturedImage? image;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          Image.file(File(image!.path), fit: BoxFit.cover)
        else
          const ColoredBox(color: AppColors.surface),
        const Positioned(
          left: 12,
          top: 10,
          child: _FaceTag(text: 'FRONT ✓', color: AppColors.emerald),
        ),
      ],
    );
  }
}

class _BackFace extends StatelessWidget {
  const _BackFace();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.25),
            AppColors.surface,
          ],
        ),
      ),
      child: const Stack(
        children: [
          Center(
            child: Icon(Icons.flip_rounded, size: 44, color: AppColors.violet),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: _FaceTag(text: 'BACK ?', color: AppColors.violet),
          ),
        ],
      ),
    );
  }
}

class _FaceTag extends StatelessWidget {
  const _FaceTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.onyx.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
