import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/hf_api/mobile_suitability.dart';
import '../../../data/hf_api/models/hf_model_summary.dart';
import '../state/listing_download_controller.dart';
import 'license_chip.dart';
import 'listing_download_button.dart';

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
      trailing: ListingDownloadButton(repoId: model.id, displayName: model.id),
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
