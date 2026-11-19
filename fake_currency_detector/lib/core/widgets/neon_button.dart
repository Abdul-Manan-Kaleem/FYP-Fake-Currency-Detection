/// The two button styles used in the app: [NeonButton] and [GhostButton].
///
/// Both give a small vibration (haptic tap) when pressed.
library;

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

  /// Text shown on the button.
  final String label;

  /// Called when tapped. If null, the button is disabled and greyed out.
  final VoidCallback? onPressed;

  /// Optional icon shown before the label.
  final IconData? icon;

  /// Main colour of the button.
  final Color color;

  /// Whether the glow slowly pulses.
  final bool pulse;

  /// True = button fills the full width; false = only as wide as needed.
  final bool expanded;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

/// Holds the glow animation and the "is pressed" flag for [NeonButton].
class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  // Glow animation: 0 to 1 and back, each trip taking 1.6 seconds.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  // True while the finger is down; makes the button shrink slightly.
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _glow.repeat(reverse: true);
  }

  // Free the animation resources when the widget is removed.
  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A button with no onPressed is disabled and uses a muted colour.
    final enabled = widget.onPressed != null;
    final color = enabled ? widget.color : AppColors.textMuted;

    // The outer glow is rebuilt on every animation tick; the button itself
    // (the `child` below) is built only once.
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        // Glow strength (0 to 1); fixed at 0.5 when not pulsing.
        final t = widget.pulse && enabled ? _glow.value : 0.5;
        // Shrink to 97% while pressed.
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
          // Track finger down/up to drive the press-shrink effect.
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

  /// Text shown on the button.
  final String label;

  /// Called when tapped. If null, the button is disabled.
  final VoidCallback? onPressed;

  /// Optional icon shown before the label.
  final IconData? icon;

  /// Colour of the text, icon and border.
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
