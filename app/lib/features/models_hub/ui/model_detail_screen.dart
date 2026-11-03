/// Model detail screen (T5 §3, reworked; D5/D6 daily-assistant pass): the
/// human model name is the title with the repo id as a caption, then ONE
/// prominent "Recommended download" card (the device-appropriate default quant
/// in plain words, verdict, a single big Download button) BEFORE the license
/// details, and finally a COLLAPSED "Other versions (advanced)" section with
/// the full per-file list, where the technical labels (Q4_K_M and friends)
/// live. A gated repo has no download to lead with, so its explanation leads
/// instead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/device_info/device_info_service.dart';
import '../../../core/device_info/model_tier.dart';
import '../../../core/di/providers.dart';
import '../../../core/failures/failure_message.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/bottom_inset.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/hf_api/default_quant.dart';
import '../../../data/hf_api/models/model_license_info.dart';
import '../../../data/hf_api/models/quant_variant.dart';
import '../state/download_actions_controller.dart';
import '../state/downloads_controller.dart';
import '../state/model_detail_provider.dart';
import '../widgets/download_progress_ring.dart';
import '../widgets/license_chip.dart';
import '../widgets/quant_quality.dart';
import '../widgets/verdict_chip.dart';

class ModelDetailScreen extends ConsumerWidget {
  final String repoId;
  const ModelDetailScreen({super.key, required this.repoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(modelDetailProvider(repoId));
    return Scaffold(
      // D5: the human name, not the raw repo id (that is the caption below).
      appBar: AppBar(
        title: Text(humanModelName(repoId), overflow: TextOverflow.ellipsis),
      ),
      body: switch (detail) {
        AsyncData(:final value) => _DetailBody(repoId: repoId, data: value),
        AsyncError(:final error) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(modelDetailProvider(repoId)),
        ),
        _ => const Center(child: DhruvaLoader()),
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
    // The default quant a normal user gets — the same rule the search-listing
    // one-tap download uses (`pickDefaultQuant`), so "Download" here and there
    // agree. Null only when the repo has no recognizable GGUF quant.
    final recommended = pickDefaultQuant(data.quants);

    final gated = data.license.requiresAuth;
    final theme = Theme.of(context);

    final licenseSection = <Widget>[
      Text('License & access', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          LicenseChip(license: data.license.license),
          GatedBadge(status: data.license.gatedStatus),
        ],
      ),
    ];
    final gatedNotice = gated
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'This repo is gated on Hugging Face — it requires signing '
                  "in and accepting the license there. ${AppIdentity.shortName} doesn't "
                  "support Hugging Face sign-in yet, so this repo's files "
                  "can't be downloaded from here.",
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          )
        : null;

    return ListView(
      padding: const EdgeInsets.all(16).withBottomInset(context),
      children: [
        // D5: title block. The human name is the headline, the repo id a
        // small caption underneath.
        Text(humanModelName(repoId), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        SelectableText(
          repoId,
          key: const ValueKey('repo-id-caption'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (data.quants.isEmpty) ...[
          const EmptyStateView(
            message: 'No downloadable model files in this repo.',
          ),
          const SizedBox(height: 24),
          ...licenseSection,
          ?gatedNotice,
        ] else ...[
          // A gated repo has nothing downloadable: its explanation leads.
          if (gated) ...[
            ...licenseSection,
            ?gatedNotice,
            const SizedBox(height: 24),
          ],
          // PRIMARY flow: one obvious download of the right file, ahead of
          // the license details.
          if (recommended != null && !gated)
            _RecommendedDownloadCard(
              repoId: repoId,
              quant: recommended,
              license: data.license,
              memory: data.memory,
            ),
          const SizedBox(height: 16),
          // Details: license sits after the action, not before it.
          if (!gated) ...[...licenseSection, const SizedBox(height: 16)],
          // SECONDARY flow: every file, collapsed; jargon labels live here.
          _AdvancedQuants(repoId: repoId, data: data),
        ],
      ],
    );
  }
}

/// The prominent, device-aware "download the right file" card. Reuses
/// `pickDefaultQuant` + `classifyModelTier` (same logic the recommended rail
/// and the listing one-tap download use) and the shared
/// [_QuantDownloadButton] so its state machine (ring / Installed / Download)
/// matches the advanced list exactly.
class _RecommendedDownloadCard extends StatelessWidget {
  final String repoId;
  final QuantVariant quant;
  final ModelLicenseInfo license;
  final DeviceMemoryInfo memory;

  const _RecommendedDownloadCard({
    required this.repoId,
    required this.quant,
    required this.license,
    required this.memory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final mmprojSizeBytes = quant.mmprojFile?.sizeBytes ?? 0;
    final tier = classifyModelTier(
      fileSizeBytes: quant.file.sizeBytes,
      totalRamBytes: memory.totalBytes,
      quant: quant.label,
      mmprojSizeBytes: mmprojSizeBytes,
    );

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommended download',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Best pick for your device — the right file, one tap.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              quant.isVision
                  ? '${plainQuantName(quant.label)} · '
                        '${_formatBytes(quant.file.sizeBytes)} '
                        '+ ${_formatBytes(mmprojSizeBytes)} for photos'
                  : '${plainQuantName(quant.label)} · '
                        '${_formatBytes(quant.file.sizeBytes)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            // Honest verdict. When nothing fits (tier == notRecommended) show
            // the gentle "May be slow" framing (mirrors recommended_rail.dart's
            // Amendment-7 fallback) instead of a scary red "Not recommended"
            // chip on the PRIMARY call to action — the user can still choose to
            // download.
            if (tier == ModelTier.notRecommended)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: tokens.warning),
                  SizedBox(width: tokens.spacing.xs),
                  Flexible(
                    child: Text(
                      'May be slow on your device',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.warning,
                      ),
                    ),
                  ),
                ],
              )
            else
              ModelVerdictChip(
                tier: tier,
                fileSizeBytes: quant.file.sizeBytes,
                totalRamBytes: memory.totalBytes,
                mmprojSizeBytes: mmprojSizeBytes,
              ),
            const SizedBox(height: 16),
            _QuantDownloadButton(
              repoId: repoId,
              quant: quant,
              license: license,
              big: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed "Other versions (advanced)" section: an [ExpansionTile]
/// (closed by default) wrapping the full per-file list. This is the secondary
/// path — a power user opens it to pick a specific version, and it is the one
/// place the technical labels (Q4_K_M, quantization) appear.
class _AdvancedQuants extends StatelessWidget {
  final String repoId;
  final ModelDetailData data;
  const _AdvancedQuants({required this.repoId, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          'Other versions (advanced)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          '${data.quants.length} files · for people who know their way around',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: data.quants
            .map(
              (quant) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuantTile(
                  repoId: repoId,
                  quant: quant,
                  license: data.license,
                  memory: data.memory,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _QuantTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    final quality = classifyQuantQuality(quant.label);

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
            // Quality/effectiveness guidance (heuristic from the quant name,
            // not a measured benchmark) so the size↔quality tradeoff is
            // visible, not just the file size.
            QuantQualityChip(quality: quality),
            const SizedBox(height: 4),
            Text(
              quality.blurb,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _QuantDownloadButton(
              repoId: repoId,
              quant: quant,
              license: license,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared download affordance for a single quant — used by BOTH the
/// recommended card ([big] = full-width) and each advanced-list tile. Owns the
/// per-taskId state machine: gated → an explanation (no button); active → the
/// live [DownloadProgressRing]; complete → "Installed"; else → the Download
/// button (routing a vision quant through `enqueueVisionQuant` so its paired
/// mmproj projector rides along). Kept in one place so the two call sites can
/// never drift apart.
class _QuantDownloadButton extends ConsumerWidget {
  final String repoId;
  final QuantVariant quant;
  final ModelLicenseInfo license;
  final bool big;

  const _QuantDownloadButton({
    required this.repoId,
    required this.quant,
    required this.license,
    this.big = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // Watch the REAL per-taskId progress stream so a running download shows a
    // persistent ring (not a button that snaps back the instant enqueue
    // returns) — same feed the listing row and Downloads screen use.
    final progress = ref
        .watch(downloadsControllerProvider)
        .value?[request.taskId];

    if (license.requiresAuth) {
      return Align(
        alignment: big ? Alignment.centerLeft : Alignment.centerRight,
        child: const Text('Requires Hugging Face sign-in — not supported yet'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: big ? Alignment.center : Alignment.centerRight,
          child: _affordance(context, ref, request, pending, progress),
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
    );
  }

  Widget _affordance(
    BuildContext context,
    WidgetRef ref,
    DownloadRequest request,
    bool pending,
    DownloadProgress? progress,
  ) {
    final state = progress?.state;
    final isActive =
        state == DownloadState.queued ||
        state == DownloadState.running ||
        state == DownloadState.paused ||
        state == DownloadState.verifying;
    if (isActive) {
      final total = progress!.totalBytes ?? 0;
      final fraction = total > 0
          ? (progress.downloadedBytes / total).clamp(0.0, 1.0)
          : 0.0;
      final ring = DownloadProgressRing(
        progress: fraction,
        onCancel: () => ref
            .read(downloadsControllerProvider.notifier)
            .cancel(request.taskId),
      );
      // Honest ETA/speed under the ring when the backend has an estimate;
      // `etaLabel` is null (renders nothing) until it does — no "--:-- left".
      final eta = progress.etaLabel;
      if (eta == null) return ring;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ring,
          const SizedBox(height: 4),
          Text(
            eta,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    if (state == DownloadState.complete) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18),
          SizedBox(width: 6),
          Text('Installed'),
        ],
      );
    }
    final button = FilledButton.icon(
      icon: pending
          // The button is disabled while pending, so its fill is the M3
          // disabled surface (not `primary`); an `onPrimary` star would be
          // near-invisible there. Let the loader default to `primary` (gold),
          // which reads clearly and matches the still-visible label.
          ? const DhruvaLoader(size: 16)
          : const Icon(Icons.download),
      label: Text(pending ? 'Starting…' : 'Download'),
      // A vision quant also enqueues its paired mmproj projector (Loop-7 T2
      // D2) — same resumable DownloadManager, chained after the model file
      // completes. A plain quant keeps using the controller's generic enqueue.
      onPressed: pending
          ? null
          : () => quant.isVision
                ? ref
                      .read(downloadActionsControllerProvider.notifier)
                      .enqueueVisionQuant(
                        repoId: repoId,
                        quant: quant,
                        license: license,
                      )
                : ref
                      .read(downloadActionsControllerProvider.notifier)
                      .enqueue(request),
    );
    // The recommended card wants ONE big, full-width call to action; the
    // advanced tiles keep the compact right-aligned button.
    return big ? SizedBox(width: double.infinity, child: button) : button;
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
