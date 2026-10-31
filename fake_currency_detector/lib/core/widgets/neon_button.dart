import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/haptics.dart';

/// Primary call-to-action with a breathing neon glow.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.cyan,
    this.pulse = true,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool pulse;
  final bool expanded;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _glow.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? widget.color : AppColors.textMuted;

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final t = widget.pulse && enabled ? _glow.value : 0.5;
        return AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: widget.expanded ? double.infinity : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25 + 0.3 * t),
                        blurRadius: 18 + 14 * t,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onTap: enabled
              ? () {
                  Haptics.tap();
                  widget.onPressed!();
                }
              : null,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.95),
                  Color.lerp(color, Colors.white, 0.25)!,
                ],
              ),
            ),
            child: Row(
              mainAxisSize:
                  widget.expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: AppColors.onyx, size: 20),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onyx,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary action that matches the glass aesthetic.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.textPrimary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed == null
          ? null
          : () {
              Haptics.tap();
              onPressed!();
            },
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.4),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
        backgroundColor: Colors.white.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
