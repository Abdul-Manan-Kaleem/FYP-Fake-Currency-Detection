import 'package:flutter/material.dart';

/// Fade + rise + subtle scale transition used for every route.
class CyberPageTransitionsBuilder extends PageTransitionsBuilder {
  const CyberPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final exiting = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 1.0, end: 0.96).animate(exiting),
          child: FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.4).animate(exiting),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Convenience route that uses the app-wide cyber transition.
class CyberRoute<T> extends MaterialPageRoute<T> {
  CyberRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);
}
