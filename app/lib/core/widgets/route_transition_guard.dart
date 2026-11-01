/// Ignores pointer input while this screen's own route is still animating in.
///
/// A new route is interactive from its first frame, so a finger that is still
/// coming down on the button that opened it (or a second tap on it) lands on
/// whatever the new screen has under that spot: "Continue to Today" would tap
/// Today's first card. Wrapping the destination in this guard swallows those
/// taps until the transition has finished. Outside a route animation (cold
/// start, tab switches, tests with no route) it does nothing.
library;

import 'package:flutter/widgets.dart';

class RouteTransitionGuard extends StatelessWidget {
  const RouteTransitionGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => IgnorePointer(
        ignoring: animation.status != AnimationStatus.completed,
        child: child,
      ),
    );
  }
}
