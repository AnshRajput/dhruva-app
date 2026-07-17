import 'package:flutter/material.dart';

import '../../../data/hf_api/models/hf_model_summary.dart';
import 'license_chip.dart';

/// One search result row: name, downloads count, likes, license chip,
/// gated badge (T5 §2).
class ModelListTile extends StatelessWidget {
  final HfModelSummary model;
  final VoidCallback onTap;

  const ModelListTile({super.key, required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      title: Text(
        model.id,
        style: textTheme.titleMedium,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download, size: 14),
                const SizedBox(width: 2),
                Text(_compact(model.downloads)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite, size: 14),
                const SizedBox(width: 2),
                Text(_compact(model.likes)),
              ],
            ),
            LicenseChip(license: model.license.license),
            GatedBadge(status: model.license.gatedStatus),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
