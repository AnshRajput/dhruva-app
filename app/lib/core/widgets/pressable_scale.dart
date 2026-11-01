/// Press feedback for custom tappable surfaces: scales to 0.97 on pointer-down
/// (instant, ease-out, 120ms) and back on release/cancel. Feedback starts on
/// press, not on release (emil-design-eng / apple-design: respond on
/// pointer-down). The scale IS the feedback (no ripple), so wrap the
/// decorated surface itself. It never delays or swallows the tap.
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: enabled ? (_) => _set(true) : null,
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          // Press in fast; release uses the same short ease-out.
          duration: const Duration(milliseconds: 120),
          curve: TokenMotionCurve.decelerate,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
