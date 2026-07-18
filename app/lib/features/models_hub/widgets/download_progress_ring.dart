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
///    keeps the ≥44px hit target.
///  - a11y: a bare `CircularProgressIndicator` announces nothing. A
///    `Semantics` label on the ring makes a screen reader say "Downloading,
///    50%", separately from the cancel button.
///
/// WS4 fix: cancel is a DISTINCT centred X, not the whole ring. The old
/// design wired the entire ring's `onTap` straight to cancel and rendered a
/// passive centred percent, so a first-time user watching progress would tap
/// the ring and silently kill a several-hundred-MB download with no undo.
/// Now the ring only shows progress; the explicit X (mirroring the Downloads
/// screen's cancel affordance) is the sole destructive target.
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
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Semantics(
            label: indeterminate ? 'Downloading' : 'Downloading, $pct%',
            child: CircularProgressIndicator(
              value: indeterminate ? null : clamped,
              strokeWidth: 3,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 18,
            tooltip: 'Cancel download',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
