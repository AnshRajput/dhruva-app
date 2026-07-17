/// Downloads screen (T5 §4): active tasks with progress + pause/resume/
/// cancel, plus a completed section reading installed models from
/// `storageManagerProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/downloads/download_manager.dart';
import '../state/downloads_controller.dart';
import '../state/storage_controller.dart';
import '../widgets/download_progress_tile.dart';
import '../widgets/failure_view.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: switch (downloads) {
        AsyncData(:final value) => ListView(
          children: [
            _ActiveSection(progress: value),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Installed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const _CompletedSection(),
          ],
        ),
        AsyncError(:final error) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(downloadsControllerProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ActiveSection extends ConsumerWidget {
  final Map<String, DownloadProgress> progress;
  const _ActiveSection({required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = progress.values
        .where(
          (p) =>
              p.state != DownloadState.complete &&
              p.state != DownloadState.canceled,
        )
        .toList();
    if (active.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No active downloads.'),
      );
    }
    return Column(
      children: active.map((p) {
        if (p.state == DownloadState.failed) {
          return _FailedDownloadTile(
            progress: p,
            onRetry: () =>
                ref.read(downloadsControllerProvider.notifier).retry(p.taskId),
            onDismiss: () =>
                ref.read(downloadsControllerProvider.notifier).cancel(p.taskId),
          );
        }
        return DownloadProgressTile(
          progress: p,
          onPause: p.state == DownloadState.running
              ? () => ref
                    .read(downloadsControllerProvider.notifier)
                    .pause(p.taskId)
              : null,
          onResume: p.state == DownloadState.paused
              ? () => ref
                    .read(downloadsControllerProvider.notifier)
                    .resume(p.taskId)
              : null,
          onCancel: () =>
              ref.read(downloadsControllerProvider.notifier).cancel(p.taskId),
        );
      }).toList(),
    );
  }
}

/// A failed download's row: file name, failure message, Retry (re-enqueue
/// via `DownloadsController.retry`) and Dismiss (drop the row — same as
/// `cancel`, safe on an already-inactive task).
class _FailedDownloadTile extends StatelessWidget {
  final DownloadProgress progress;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _FailedDownloadTile({
    required this.progress,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(progress.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${progress.repoId} · failed'),
            if (progress.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  progress.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _CompletedSection extends ConsumerWidget {
  const _CompletedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageControllerProvider);
    return switch (storage) {
      AsyncData(:final value) =>
        value.installed.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing installed yet.'),
              )
            : Column(
                children: value.installed
                    .map(
                      (m) => ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(m.repoId, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${m.fileName}${m.quant != null ? ' · ${m.quant}' : ''}',
                        ),
                      ),
                    )
                    .toList(),
              ),
      AsyncError() => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Could not load installed models.'),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}
