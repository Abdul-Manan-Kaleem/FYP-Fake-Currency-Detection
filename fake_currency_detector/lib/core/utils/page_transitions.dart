/// Custom animation played when the app moves from one screen to another.
///
/// The theme (app_theme.dart) registers it, and [CyberRoute] uses it.
library;

import 'package:flutter/material.dart';

/// Fade + rise + subtle scale transition used for every route.
class CyberPageTransitionsBuilder extends PageTransitionsBuilder {
  const CyberPageTransitionsBuilder();

  /// Wraps the new page in the animation widgets.
  /// [animation] runs while this page enters; [secondaryAnimation] runs
  /// while another page opens on top of it.
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Smooth the entering animation (fast start, slow end).
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // Same smoothing for when this page is covered by a newer page.
    final exiting = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    // Layers: fade in, slide up slightly, shrink to 96% and dim to 40% when
    // covered by another page.
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

  /// Time taken to open the page.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  /// Time taken to close the page (a bit quicker than opening).
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);
}
