import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/hf_api/mobile_suitability.dart';
import '../../../data/hf_api/models/hf_model_summary.dart';
import '../state/listing_download_controller.dart';
import 'download_progress_ring.dart';
import 'license_chip.dart';

/// One search result row: name, downloads/likes, license + gated chips, a
/// mobile-suitability hint, and an inline download state machine (Phase B,
/// D1-D3): Download → progress ring (cancellable) → Installed (Chat + Delete).
/// Tapping the row itself still opens the detail screen (the quant-picker
/// path); the trailing affordance is the seamless default-quant path.
class ModelListTile extends ConsumerWidget {
  final HfModelSummary model;
  final VoidCallback onTap;

  const ModelListTile({super.key, required this.model, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final states = ref.watch(listingDownloadControllerProvider).value;
    final state = states?[model.id] ?? const ListingModelState();
    final suitability = mobileSuitabilityOf(model.id);

    return ListTile(
      onTap: onTap,
      title: Text(
        model.id,
        style: textTheme.titleMedium,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine:
          state.status == ListingModelStatus.failed &&
          state.errorMessage != null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _stat(Icons.download, _compact(model.downloads)),
                _stat(Icons.favorite, _compact(model.likes)),
                LicenseChip(license: model.license.license),
                GatedBadge(status: model.license.gatedStatus),
                _SuitabilityChip(suitability: suitability),
              ],
            ),
          ),
          if (state.status == ListingModelStatus.failed &&
              state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      trailing: _Trailing(model: model, state: state),
    );
  }

  Widget _stat(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 14), const SizedBox(width: 2), Text(label)],
  );

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _Trailing extends ConsumerWidget {
  final HfModelSummary model;
  final ListingModelState state;
  const _Trailing({required this.model, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(listingDownloadControllerProvider.notifier);
    switch (state.status) {
      case ListingModelStatus.notInstalled:
        return IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download',
          onPressed: () => notifier.download(model.id),
        );
      case ListingModelStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: () => notifier.download(model.id),
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
          onCancel: () => notifier.cancel(model.id),
        );
      case ListingModelStatus.installed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat',
              // QA Phase B: carry the installed model so tapping Chat starts a
              // LOADED conversation, not a bare /chat with no model selected
              // (the app's own model-picker flow uses `extra: <drift row id>`
              // → ChatRouteArgs.initialModelId). A null id can't happen in the
              // installed state, but guard rather than force-unwrap.
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

  Future<void> _confirmDelete(
    BuildContext context,
    ListingDownloadController notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('This removes ${model.id} from this device.'),
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
    if (confirmed == true) await notifier.delete(model.id);
  }
}

class _SuitabilityChip extends StatelessWidget {
  final MobileSuitability suitability;
  const _SuitabilityChip({required this.suitability});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (suitability) {
      MobileSuitability.friendly => (
        'Mobile-friendly',
        theme.colorScheme.primary,
        Icons.smartphone,
      ),
      MobileSuitability.heavy => (
        'Large model',
        theme.colorScheme.error,
        Icons.warning_amber,
      ),
      // Unknown/mid-size: no chip — nothing useful to say.
      MobileSuitability.neutral => (null, null, null),
    };
    if (label == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
