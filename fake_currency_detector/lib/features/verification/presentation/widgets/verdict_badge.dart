import 'package:flutter/material.dart';

import '../../data/models/verification_result_model.dart';
import 'verdict_style.dart';

/// Pill badge with a breathing glow that pops in on first build.
class VerdictBadge extends StatefulWidget {
  const VerdictBadge({super.key, required this.verdict});

  final VerificationVerdict verdict;

  @override
  State<VerdictBadge> createState() => _VerdictBadgeState();
}

class _VerdictBadgeState extends State<VerdictBadge>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _intro.forward();
      _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.verdict.color;
    return ScaleTransition(
      scale: CurvedAnimation(parent: _intro, curve: Curves.elasticOut),
      child: FadeTransition(
        opacity: _intro,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25 + 0.3 * _pulse.value),
                  blurRadius: 16 + 14 * _pulse.value,
                ),
              ],
            ),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.verdict.icon, color: color, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.verdict.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
