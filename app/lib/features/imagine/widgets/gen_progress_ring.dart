/// Generation-step progress ring (Loop 8 T2). Same shape as models_hub's
/// `DownloadProgressRing` (determinate ring + a real ≥44px cancel target +
/// an announcing `Semantics` wrapper) — duplicated rather than imported
/// since `features/imagine` can't reach into `features/models_hub`
/// (ADR-002: no cross-feature imports; both are two small, independent
/// "ring around a cancel button" widgets, not worth promoting to `core/`
/// for one shared caller each).
library;

import 'package:flutter/material.dart';

class GenProgressRing extends StatelessWidget {
  /// 0..1. 0 (or unknown total) renders an indeterminate spinner.
  final double progress;
  final VoidCallback onCancel;

  const GenProgressRing({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final indeterminate = clamped == 0;
    final pct = (clamped * 100).round();
    return Semantics(
      label: 'Generating image',
      value: indeterminate ? 'in progress' : '$pct%',
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: indeterminate ? null : clamped,
              strokeWidth: 3,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Cancel generation',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
