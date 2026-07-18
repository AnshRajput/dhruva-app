/// Downloads screen (T5 §4): active tasks with progress + pause/resume/
/// cancel, a "Ready — start chatting" section for models that finished this
/// session (with a direct CTA into a loaded chat — WS4), plus a completed
/// section reading installed models from `storageManagerProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../data/models/starter_catalog.dart';
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
            _ReadySection(progress: value),
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

/// WS4: models that FINISHED downloading this session get an unmissable
/// "Ready — start chatting" card with a button that opens a chat already
/// loaded with that model — closing the download→chat loop without making the
/// user hunt for the model in a picker. Voice bundles ride the same download
/// pipeline (`sherpa-voice/` repoId) but aren't a chat pick, so they're
/// excluded here — they surface in their own Voice tab. A vision model's mmproj
/// projector rides the same pipeline (`registerAsInstalledModel: false`, same
/// vision repoId) but never becomes its own installed model, so it's excluded
/// too — otherwise it renders a bogus "Ready" card whose CTA opens a model-less
/// chat.
class _ReadySection extends ConsumerWidget {
  final Map<String, DownloadProgress> progress;
  const _ReadySection({required this.progress});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve each finished download to its installed drift row so the CTA
    // can open a chat with THAT exact model loaded. The Installed list is kept
    // fresh by AppShell's invalidate-on-completion, so the row exists by now.
    final installed =
        ref.watch(storageControllerProvider).value?.installed ??
        const <InstalledModelInfo>[];

    final ready = progress.values
        .where(
          (p) =>
              p.state == DownloadState.complete &&
              p.registerAsInstalledModel &&
              !p.repoId.startsWith('sherpa-voice/') &&
              // A vision model's GGUF completing does NOT make it chat-ready —
              // its mmproj projector still has to land. Hold the "Ready" card
              // until the installed row shows the projector attached
              // (!needsProjector); the row re-reads when the projector's own
              // completion invalidates storageController, flipping this true.
              _visionProjectorReady(p, installed),
        )
        .toList();
    if (ready.isEmpty) return const SizedBox.shrink();

    return Column(
      children: ready
          .map(
            (p) => _ReadyTile(
              progress: p,
              modelId: installed
                  .where(
                    (m) => m.repoId == p.repoId && m.fileName == p.fileName,
                  )
                  .map((m) => m.id)
                  .firstOrNull,
            ),
          )
          .toList(),
    );
  }

  /// True unless [p] is a vision model still missing its projector: a
  /// non-vision download is always ready; a vision one is ready only once its
  /// installed row exists AND has the mmproj attached.
  static bool _visionProjectorReady(
    DownloadProgress p,
    List<InstalledModelInfo> installed,
  ) {
    if (!p.isVision) return true;
    final row = installed
        .where((m) => m.repoId == p.repoId && m.fileName == p.fileName)
        .firstOrNull;
    return row != null && !row.needsProjector;
  }
}

class _ReadyTile extends StatelessWidget {
  final DownloadProgress progress;
  final int? modelId;
  const _ReadyTile({required this.progress, this.modelId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      color: tokens.success.withValues(alpha: 0.12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        side: BorderSide(color: tokens.success.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        leading: Icon(Icons.check_circle, color: tokens.success),
        title: Text(
          friendlyModelName(progress.repoId),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('Ready — start chatting'),
        trailing: FilledButton(
          onPressed: () => modelId != null
              ? context.push('/chat/new', extra: modelId)
              // No resolved id (edge: row not yet visible) — still route into
              // chat, where the picker lists the freshly-installed model.
              : context.push('/chat/new'),
          child: const Text('Start chatting'),
        ),
      ),
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
      title: Text(
        friendlyModelName(progress.repoId),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Failed'),
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
                        title: Text(
                          friendlyModelName(m.repoId),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(m.quant ?? m.fileName),
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
