/// The trailing download state machine shared by every "one-tap download a
/// repo's default quant" surface: the advanced-search result rows
/// (`ModelListTile`) and the curated catalog cards (`CuratedModelCard`).
///
/// Driven entirely by `ListingDownloadController` (keyed by repoId):
/// Download → resolving spinner → progress ring (cancellable) → Installed
/// (Chat + Delete). Extracted so both surfaces share ONE state machine
/// instead of re-implementing it per widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/listing_download_controller.dart';
import 'download_progress_ring.dart';

class ListingDownloadButton extends ConsumerWidget {
  final String repoId;

  /// Human-friendly label for the delete confirmation ("Delete {name}?") —
  /// the curated card passes its friendly display name; a raw search row
  /// passes the repo id.
  final String displayName;

  const ListingDownloadButton({
    super.key,
    required this.repoId,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(listingDownloadControllerProvider).value;
    final state = states?[repoId] ?? const ListingModelState();
    final notifier = ref.read(listingDownloadControllerProvider.notifier);

    switch (state.status) {
      case ListingModelStatus.notInstalled:
        return IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download',
          onPressed: () => notifier.download(repoId),
        );
      case ListingModelStatus.oversizeWarning:
        // Not a dead-end: an informed "download anyway" — a warning-tinted
        // download button that confirms the "may be slow" tradeoff, then
        // forces the download (mirrors the model detail screen, which
        // downloads the same below-floor file after the same note).
        return IconButton(
          icon: const Icon(Icons.download_outlined),
          color: Theme.of(context).colorScheme.tertiary,
          tooltip: 'Download anyway',
          onPressed: () =>
              _confirmOversize(context, notifier, state.errorMessage),
        );
      case ListingModelStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: () => notifier.download(repoId),
        );
      case ListingModelStatus.resolving:
        return const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case ListingModelStatus.downloading:
        return DownloadProgressRing(
          progress: state.progress,
          onCancel: () => notifier.cancel(repoId),
        );
      case ListingModelStatus.installed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat',
              // Carry the installed model's drift row id so tapping Chat
              // starts a LOADED conversation (the app's model-picker flow
              // uses `extra: <drift row id>` → ChatRouteArgs.initialModelId).
              // A null id can't happen in the installed state, but guard.
              onPressed: state.installedId == null
                  ? null
                  : () => context.push('/chat/new', extra: state.installedId),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context, notifier),
            ),
          ],
        );
    }
  }

  Future<void> _confirmOversize(
    BuildContext context,
    ListingDownloadController notifier,
    String? message,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download anyway?'),
        content: Text(message ?? 'This model may be slow on your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.download(repoId, force: true);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ListingDownloadController notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('This removes $displayName from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.delete(repoId);
  }
}
