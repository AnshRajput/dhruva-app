/// Wraps a horizontal scroller and fades the edge that has more content past
/// it, so a chip row never just ends in a half-cut chip with nothing saying it
/// scrolls. The fade is the scroll affordance (the comps show the same cut-off
/// chip); it disappears when everything fits.
library;

import 'package:flutter/material.dart';

class EdgeFade extends StatefulWidget {
  const EdgeFade({super.key, required this.child, this.extent = 32});

  /// A horizontal scrollable (`ListView`, `SingleChildScrollView`).
  final Widget child;

  /// Width of the fade, in logical pixels.
  final double extent;

  @override
  State<EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<EdgeFade> {
  bool _before = false;
  bool _after = false;

  bool _onMetrics(ScrollMetrics m) {
    final before = m.extentBefore > 1;
    final after = m.extentAfter > 1;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Only the alpha channel of the mask matters (dstIn).
    final solid = Theme.of(context).colorScheme.scrim;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final f = (widget.extent / rect.width).clamp(0.0, 0.5);
            return LinearGradient(
              colors: [
                if (_before) solid.withValues(alpha: 0) else solid,
                solid,
                solid,
                if (_after) solid.withValues(alpha: 0) else solid,
              ],
              stops: [0, f, 1 - f, 1],
            ).createShader(rect);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
