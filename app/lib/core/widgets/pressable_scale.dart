/// Press feedback for custom tappable surfaces: scales to 0.97 on pointer-down
/// (instant, ease-out, 120ms in / 100ms out) and back on release/cancel.
/// Feedback starts on press, not on release (emil-design-eng / apple-design:
/// respond on pointer-down). The scale IS the feedback (no ripple), so wrap the
/// decorated surface itself. It never delays or swallows the tap.
///
/// The press releases as soon as the gesture stops being a tap: the tap
/// recognizer's cancel (a scroll or drag won the arena), a pointer cancel, or
/// the finger travelling past touch slop. A bare `Listener` never hears that a
/// scroll won, which left tiles shrunk for the whole scroll.
library;

import 'package:flutter/gestures.dart' show kTouchSlop;
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
  Offset? _origin;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  void _release() {
    _origin = null;
    _set(false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: enabled
            ? (e) {
                _origin = e.position;
                _set(true);
              }
            : null,
        onPointerMove: (e) {
          final o = _origin;
          if (o != null && (e.position - o).distance > kTouchSlop) _release();
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedScale(
          // Reduced motion keeps the state change but drops the movement.
          scale: _down && !reduce ? 0.97 : 1,
          duration: _down
              ? const Duration(milliseconds: 120)
              : const Duration(milliseconds: 100),
          curve: TokenMotionCurve.decelerate,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapCancel: _release,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
