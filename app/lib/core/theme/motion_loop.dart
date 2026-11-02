/// One rule for every perpetual loop (orb, shimmer, loaders, pulses): under
/// reduced motion (`MediaQuery.disableAnimations`) the loop STOPS and rests at
/// a fixed value, so nothing moves forever (apple-design: reduced motion means
/// a calm static state, not a slower loop). Call from `didChangeDependencies`.
library;

import 'package:flutter/material.dart';

extension ReducedMotionLoop on AnimationController {
  /// Start (or keep) looping, or stop at [rest] when motion is reduced.
  /// [period] re-targets the cadence of a loop that is already running.
  void loop(
    BuildContext context, {
    Duration? period,
    bool reverse = false,
    double rest = 0.5,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) {
      stop();
      value = rest;
    } else if (!isAnimating || period != null) {
      repeat(reverse: reverse, period: period);
    }
  }
}
