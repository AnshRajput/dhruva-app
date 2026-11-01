/// Model picker bottom sheet (chat-spec.md §6.1). Opened from the AppBar
/// model chip, and from the OOM error card's "Try a smaller model"
/// affordance (pre-filtered to `comfortable`/`possible` tiers for this
/// device — reuses `core/device_info`'s existing tiering).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/device_info/model_tier.dart';
import '../../../core/di/providers.dart';
import '../../../core/di/speed_providers.dart';
import '../../../core/theme/brand_star.dart' show DhruvaLoader;
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/speed_label_chip.dart';
import '../../../data/benchmark/speed_result.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../data/hf_api/quant_quality.dart' show plainQuantName;
import '../state/installed_models_provider.dart';
import '../widgets/brand_motif.dart';
import '../widgets/model_chip.dart';

/// Returns the picked model, or null if the sheet was dismissed.
Future<InstalledModelInfo?> showModelPickerSheet(
  BuildContext context, {
  int? selectedModelId,
  bool smallerModelsOnly = false,

  /// With [smallerModelsOnly]: only installed models strictly smaller than
  /// this many bytes (the model that just failed). When none exist the
  /// sheet says so and links to Discover instead of listing a bigger model.
  int? smallerThanBytes,
}) {
  final tokens = Theme.of(context).extension<DhruvaTokens>()!;
  return showModalBottomSheet<InstalledModelInfo>(
    context: context,
    isScrollControlled: true,
    // Nit 6, chat-spec.md §10 — see sampling_settings_sheet.dart's
    // identical note: duration is sourced from the tokens, the
    // entrance/exit curve is a documented deviation (no public
    // `showModalBottomSheet` hook reads it).
    sheetAnimationStyle: AnimationStyle(
      duration: tokens.motion.moderate,
      reverseDuration: tokens.motion.fast,
    ),
    builder: (context) => _ModelPickerSheet(
      selectedModelId: selectedModelId,
      smallerModelsOnly: smallerModelsOnly,
      smallerThanBytes: smallerThanBytes,
    ),
  );
}

class _ModelPickerSheet extends ConsumerWidget {
  final int? selectedModelId;
  final bool smallerModelsOnly;
  final int? smallerThanBytes;

  const _ModelPickerSheet({
    this.selectedModelId,
    required this.smallerModelsOnly,
    this.smallerThanBytes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final modelsAsync = ref.watch(installedModelsProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              smallerModelsOnly ? 'Use a smaller model' : 'Choose a model',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: tokens.spacing.sm),
            switch (modelsAsync) {
              AsyncData(:final value) => _ModelList(
                models: value,
                selectedModelId: selectedModelId,
                smallerModelsOnly: smallerModelsOnly,
                smallerThanBytes: smallerThanBytes,
              ),
              AsyncError(:final error) => ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(installedModelsProvider),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: DhruvaLoader()),
              ),
            },
            // Loop 7: "no vision model installed but the user wants vision"
            // (LOOP-07 PLAN) — a discoverable path to the model library,
            // where vision quants are browsable/downloadable (`features/
            // models_hub`'s catalog, Loop-7 T2), not a dedicated vision rail
            // built in `features/chat`'s own scope.
            if (modelsAsync case AsyncData(
              :final value,
            ) when value.every((m) => !m.isVision))
              Padding(
                padding: EdgeInsets.only(top: tokens.spacing.xs),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/models/hub');
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
                    child: Text(
                      'Want to chat about photos? Browse vision models →',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelList extends ConsumerWidget {
  final List<InstalledModelInfo> models;
  final int? selectedModelId;
  final bool smallerModelsOnly;
  final int? smallerThanBytes;

  const _ModelList({
    required this.models,
    required this.selectedModelId,
    required this.smallerModelsOnly,
    this.smallerThanBytes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (models.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No models installed yet.'),
      );
    }
    if (!smallerModelsOnly) return _list(context, ref, models);
    final cap = smallerThanBytes;
    if (cap != null) {
      final smaller = models.where((m) => m.sizeBytes < cap).toList();
      if (smaller.isEmpty) return const _NoSmallerModel();
      return _list(context, ref, smaller);
    }

    return FutureBuilder<DeviceMemoryInfo>(
      future: ref.read(deviceInfoServiceProvider).getMemoryInfo(),
      builder: (context, snapshot) {
        final memory = snapshot.data;
        if (memory == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: DhruvaLoader()),
          );
        }
        final filtered = models.where((m) {
          final tier = classifyModelTier(
            fileSizeBytes: m.sizeBytes,
            totalRamBytes: memory.totalBytes,
          );
          return tier != ModelTier.notRecommended;
        }).toList();
        return _list(context, ref, filtered.isEmpty ? models : filtered);
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<InstalledModelInfo> items,
  ) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final results = ref.watch(speedResultsProvider).value ?? const {};
    return ListView.builder(
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final model = items[i];
        final selected = model.id == selectedModelId;
        return ListTile(
          leading: selected
              ? DhruvaStar(size: 20, color: theme.colorScheme.primary)
              : const SizedBox(width: 20),
          title: Text(
            modelShortLabel(model.repoId),
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plainQuantName(model.quant)} · ${_formatBytes(model.sizeBytes)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tokens.spacing.xs),
              SpeedLabelChip(
                result: results[speedKey(model.repoId, model.fileName)],
              ),
            ],
          ),
          onTap: () => Navigator.of(context).pop(model),
        );
      },
    );
  }
}

/// Nothing installed is smaller than the failed model: say so and point at
/// Discover, rather than offering a bigger model as a "smaller" one.
class _NoSmallerModel extends StatelessWidget {
  const _NoSmallerModel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have no smaller model installed.',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: tokens.spacing.sm),
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/models/hub');
            },
            child: const Text('Find a smaller model'),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
