/// Status pill shown on Today while any model download is active, so the
/// Downloads screen stays one tap away now that Models lives under Settings
/// (spec: "Downloads stays reachable from a status pill when active").
/// Renders nothing when no download is running.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/downloads/download_manager.dart';
import '../state/downloads_controller.dart';

bool isDownloadActive(DownloadProgress progress) => switch (progress.state) {
  DownloadState.queued ||
  DownloadState.running ||
  DownloadState.paused ||
  DownloadState.verifying => true,
  DownloadState.complete ||
  DownloadState.failed ||
  DownloadState.canceled => false,
};

class DownloadStatusPill extends ConsumerWidget {
  const DownloadStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsControllerProvider).value ?? const {};
    final active = downloads.values.where(isDownloadActive).length;
    if (active == 0) return const SizedBox.shrink();
    return ActionChip(
      key: const ValueKey('download-status-pill'),
      avatar: const Icon(Icons.downloading_rounded, size: 18),
      label: Text(active == 1 ? 'Downloading a model' : '$active downloads'),
      // Downloads is a full-screen route, safe to push from the shell.
      onPressed: () => context.push('/models/downloads'),
    );
  }
}
