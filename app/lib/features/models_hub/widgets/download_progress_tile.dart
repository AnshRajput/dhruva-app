import 'package:flutter/material.dart';

import '../../../data/downloads/download_manager.dart';

/// One active/recent download row: file name, repo, live status + percent,
/// progress bar, real speed/ETA (WS4 — surfaced from `DownloadProgress`),
/// pause/resume/cancel (T5 §4).
class DownloadProgressTile extends StatelessWidget {
  final DownloadProgress progress;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback onCancel;

  const DownloadProgressTile({
    super.key,
    required this.progress,
    this.onPause,
    this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = progress.totalBytes;
    final fraction = (total != null && total > 0)
        ? (progress.downloadedBytes / total).clamp(0.0, 1.0)
        : null;
    // Verifying has no meaningful percent (the file's already on disk, we're
    // hashing it) — show an indeterminate bar rather than a frozen 100%.
    final barValue = progress.state == DownloadState.verifying
        ? null
        : fraction;
    return ListTile(
      title: Text(progress.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_headline(fraction)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: barValue),
            if (_detailLine() case final detail?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (progress.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  progress.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (progress.state == DownloadState.running && onPause != null)
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: 'Pause',
              onPressed: onPause,
            ),
          if (progress.state == DownloadState.paused && onResume != null)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Resume',
              onPressed: onResume,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  /// "`repoId` · Downloading · 40%" — the percent only when it's known and
  /// meaningful (not for queued/verifying, which have no in-flight fraction).
  String _headline(double? fraction) {
    final showPercent =
        fraction != null &&
        (progress.state == DownloadState.running ||
            progress.state == DownloadState.paused);
    final parts = <String>[progress.repoId, _stateLabel(progress.state)];
    if (showPercent) parts.add('${(fraction * 100).round()}%');
    return parts.join(' · ');
  }

  /// "128 / 512 MB · 3.1 MB/s · 0:45 left" — real bytes plus the already-
  /// plumbed [DownloadProgress.etaLabel]; null (renders nothing) when there's
  /// nothing honest to show yet, never a fake "--:-- left".
  String? _detailLine() {
    if (progress.state != DownloadState.running &&
        progress.state != DownloadState.paused) {
      return null;
    }
    final parts = <String>[];
    final total = progress.totalBytes;
    if (total != null && total > 0) {
      parts.add(
        '${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(total)}',
      );
    }
    if (progress.state == DownloadState.running && progress.etaLabel != null) {
      parts.add(progress.etaLabel!);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _stateLabel(DownloadState state) => switch (state) {
    DownloadState.queued => 'Queued',
    DownloadState.running => 'Downloading',
    DownloadState.paused => 'Paused',
    DownloadState.verifying => 'Verifying…',
    DownloadState.complete => 'Complete',
    DownloadState.failed => 'Failed',
    DownloadState.canceled => 'Canceled',
  };
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} kB';
  return '$bytes B';
}
