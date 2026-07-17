import 'package:flutter/material.dart';

import '../../../data/hf_api/models/model_license_info.dart';

/// A repo's declared license, e.g. "apache-2.0". Shown before any download
/// affordance (Rule: user sees license first) — see model_detail_screen.dart.
class LicenseChip extends StatelessWidget {
  final String? license;
  const LicenseChip({super.key, required this.license});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(license ?? 'license unknown'),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Whether the repo is gated on Hugging Face (manual/auto approval), or
/// nothing (an empty box) when it isn't.
class GatedBadge extends StatelessWidget {
  final HfGatedStatus status;
  const GatedBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == HfGatedStatus.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.lock, size: 16, color: scheme.onErrorContainer),
      label: Text(
        status == HfGatedStatus.manual
            ? 'Gated · manual approval'
            : 'Gated · auto approval',
      ),
      backgroundColor: scheme.errorContainer,
      labelStyle: TextStyle(color: scheme.onErrorContainer),
      visualDensity: VisualDensity.compact,
    );
  }
}
