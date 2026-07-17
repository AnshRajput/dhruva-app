import 'package:flutter/material.dart';

/// The one download-in-progress affordance shared by the search-listing row
/// (`model_list_tile.dart`) and the detail-screen quant tile
/// (`model_detail_screen.dart`) — so both get the same ring, the same
/// screen-reader announcement, and the same accessible cancel target.
///
/// Designer Phase B blockers this closes in one place (route every caller
/// through it, don't fix each row):
///  - tap target: the cancel button used to collapse to ~16px
///    (`EdgeInsets.zero` + empty `BoxConstraints`). A default `IconButton`
///    inside a 48×48 box keeps the ≥44px hit target.
///  - a11y: a bare `CircularProgressIndicator` announces nothing.
///    `Semantics(label/value)` makes a screen reader say "Downloading, 50%".
class DownloadProgressRing extends StatelessWidget {
  /// 0..1. 0 (or unknown total) renders an indeterminate spinner.
  final double progress;
  final VoidCallback onCancel;

  const DownloadProgressRing({
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
      label: 'Downloading',
      value: indeterminate ? 'in progress' : '$pct%',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: indeterminate ? null : clamped,
              strokeWidth: 2,
            ),
            // Default IconButton min size is 48×48 (kMinInteractiveDimension) —
            // do NOT shrink it with zero padding/constraints; that was the bug.
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Cancel download',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
