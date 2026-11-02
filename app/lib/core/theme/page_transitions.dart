/// Android page transition: fade + an 8 px rise, 220 ms in / 180 ms out,
/// ease-out only. Replaces Flutter's `FadeForwardsPageTransitionsBuilder`
/// (450 ms, ease-in-out), which blew the 300 ms UI budget on the most-hit
/// motion in the app. Reduced motion (`MediaQuery.disableAnimations`) is a pure
/// cross-fade, no movement. iOS keeps the Cupertino slide.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

class DhruvaPageTransitionsBuilder extends PageTransitionsBuilder {
  const DhruvaPageTransitionsBuilder();

  static const _rise = 8.0;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: TokenMotionCurve.decelerate,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: fade, child: child);
    }
    // The page underneath fades back a little so the incoming page reads as
    // sitting above it, never as a hard cut.
    final under = CurvedAnimation(
      parent: secondaryAnimation,
      curve: TokenMotionCurve.decelerate,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.85).animate(under),
      child: FadeTransition(
        opacity: fade,
        child: AnimatedBuilder(
          animation: fade,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - fade.value) * _rise),
            child: child,
          ),
        ),
      ),
    );
  }
}
