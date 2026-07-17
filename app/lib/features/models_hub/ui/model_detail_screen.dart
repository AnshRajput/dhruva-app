/// Model detail screen (T5 §3): repo info, license + gated status shown
/// BEFORE any download affordance, the quant file list with per-file device
/// verdict, and a download button per file that enqueues onto
/// `downloadManagerProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/device_info/device_info_service.dart';
import '../../../core/device_info/model_tier.dart';
import '../../../core/di/providers.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/hf_api/models/model_license_info.dart';
import '../../../data/hf_api/models/quant_variant.dart';
import '../state/download_actions_controller.dart';
import '../state/failure_message.dart';
import '../state/model_detail_provider.dart';
import '../widgets/failure_view.dart';
import '../widgets/license_chip.dart';
import '../widgets/verdict_chip.dart';

class ModelDetailScreen extends ConsumerWidget {
  final String repoId;
  const ModelDetailScreen({super.key, required this.repoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(modelDetailProvider(repoId));
    return Scaffold(
      appBar: AppBar(title: Text(repoId, overflow: TextOverflow.ellipsis)),
      body: switch (detail) {
        AsyncData(:final value) => _DetailBody(repoId: repoId, data: value),
        AsyncError(:final error) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(modelDetailProvider(repoId)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  final String repoId;
  final ModelDetailData data;
  const _DetailBody({required this.repoId, required this.data});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Rule: license + gated status appear before any download
        // affordance, below.
        Text(
          'License & access',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            LicenseChip(license: data.license.license),
            GatedBadge(status: data.license.gatedStatus),
          ],
        ),
        if (data.license.requiresAuth)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'This repo is gated on Hugging Face — it requires signing '
                  "in and accepting the license there. Dhruva doesn't "
                  "support Hugging Face sign-in yet, so this repo's files "
                  "can't be downloaded from here.",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Files', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (data.quants.isEmpty)
          const EmptyStateView(
            message: 'No recognizable GGUF quant files in this repo.',
          )
        else
          ...data.quants.map(
            (quant) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QuantTile(
                repoId: repoId,
                quant: quant,
                license: data.license,
                memory: data.memory,
              ),
            ),
          ),
      ],
    );
  }
}

class _QuantTile extends ConsumerWidget {
  final String repoId;
  final QuantVariant quant;
  final ModelLicenseInfo license;
  final DeviceMemoryInfo memory;

  const _QuantTile({
    required this.repoId,
    required this.quant,
    required this.license,
    required this.memory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A vision quant's "will it run?" verdict counts the paired mmproj
    // projector's footprint too — both load into memory together (Loop-7
    // T1's `EngineLoadParams.mmprojPath`, model_tier.dart's D4).
    final mmprojSizeBytes = quant.mmprojFile?.sizeBytes ?? 0;
    final tier = classifyModelTier(
      fileSizeBytes: quant.file.sizeBytes,
      totalRamBytes: memory.totalBytes,
      quant: quant.label,
      mmprojSizeBytes: mmprojSizeBytes,
    );
    final request = DownloadRequest(
      repoId: repoId,
      fileName: p.basename(quant.file.path),
      url: ref
          .read(hfApiClientProvider)
          .resolveDownloadUrl(repoId, quant.file.path),
      expectedSizeBytes: quant.file.sizeBytes,
      expectedSha256: quant.file.sha256,
      quant: quant.label,
      license: license.license,
      gated: license.requiresAuth,
      isVision: quant.isVision,
    );
    final actions = ref.watch(downloadActionsControllerProvider);
    final pending = actions.isPending(request.taskId);
    final error = actions.errorFor(request.taskId);
    // A vision quant also enqueues its paired mmproj projector (Loop-7 T2
    // D2) — same resumable DownloadManager, chained after the model file
    // completes. A plain quant keeps using the controller's generic enqueue.
    Future<void> download() => quant.isVision
        ? ref
              .read(downloadActionsControllerProvider.notifier)
              .enqueueVisionQuant(
                repoId: repoId,
                quant: quant,
                license: license,
              )
        : ref.read(downloadActionsControllerProvider.notifier).enqueue(request);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quant.isVision
                        ? '${quant.label} · ${_formatBytes(quant.file.sizeBytes)} '
                              '+ ${_formatBytes(mmprojSizeBytes)} vision'
                        : '${quant.label} · ${_formatBytes(quant.file.sizeBytes)}',
                  ),
                ),
                const SizedBox(width: 8),
                ModelVerdictChip(
                  tier: tier,
                  fileSizeBytes: quant.file.sizeBytes,
                  totalRamBytes: memory.totalBytes,
                  mmprojSizeBytes: mmprojSizeBytes,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: license.requiresAuth
                  ? const Text(
                      'Requires Hugging Face sign-in — not supported yet',
                    )
                  : FilledButton.icon(
                      icon: pending
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(pending ? 'Starting…' : 'Download'),
                      onPressed: pending ? null : download,
                    ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  friendlyFailureMessage(error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '$bytes B';
}
