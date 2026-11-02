/// Models hub home (PRD v0.3 WS1). The DEFAULT tab is the curated,
/// phone-verified catalog (`CuratedTab`) — not the raw Hugging Face firehose,
/// which is demoted to the "Search all of Hugging Face (advanced)" screen the
/// curated tab links to. Installed + Voice are the other two tabs; downloads
/// are reachable from the app bar. One of the bottom-nav destinations (see
/// `core/router/app_shell.dart`).
library;

import 'dart:io';

// Deliberate, documented exception to ADR-002's "no plugin imports in
// features/": file picking is a pure UI/platform concern with no business
// logic — the picked `XFile`'s path is handed straight to
// `StorageController.importLocal`, which is the only place that touches
// `dart:io`/drift (see local_import.dart: "selection itself is a UI
// concern, out of scope").
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/failures/app_failure.dart';
import '../../../core/failures/failure_message.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../data/hf_api/quant_quality.dart' show plainQuantName;
import '../../../voice/voice_model_catalog.dart'
    show VoiceModelRole, voiceBundleEntries;
import '../state/recommended_models_provider.dart';
import '../state/speed_test_controller.dart';
import '../state/storage_controller.dart';
import '../state/voice_models_controller.dart';
import '../widgets/curated_tab.dart';
import '../widgets/speed_test_widgets.dart';
import '../widgets/voice_model_tile.dart';

class ModelsHubScreen extends StatelessWidget {
  /// Which tab to open on. Deep-linked callers (e.g. hands-free's "Set up
  /// voice" — WS5) pass `2` to land straight on the Voice tab instead of the
  /// default Discover tab (the curated, phone-verified catalog — the raw HF
  /// firehose now lives behind the advanced-search screen, see the class doc).
  final int initialTabIndex;

  const ModelsHubScreen({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Models'),
          actions: [
            // Parity row 37: advanced Hugging Face search must be findable
            // without scrolling to the foot of Discover.
            IconButton(
              key: const ValueKey('models-hf-search'),
              icon: const Icon(Icons.travel_explore),
              tooltip: 'Search all of Hugging Face (advanced)',
              onPressed: () => context.push('/models/search'),
            ),
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Downloads',
              onPressed: () => context.push('/models/downloads'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Discover'),
              Tab(text: 'Installed'),
              Tab(text: 'Voice'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [CuratedTab(), _InstalledTab(), _VoiceTab()],
        ),
      ),
    );
  }
}

/// Loop 6, T4/D4: the curated ASR/TTS/VAD catalog
/// (`voice/voice_model_catalog.dart`), downloadable through the same
/// `DownloadManager` GGUF models use (`voice_models_controller.dart`) — one
/// section per role so hold-to-talk's "VAD + ASR required" and TTS's
/// "pick a voice" needs read clearly at a glance.
class _VoiceTab extends ConsumerWidget {
  const _VoiceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceModelsControllerProvider);
    final notifier = ref.read(voiceModelsControllerProvider.notifier);
    return switch (state) {
      AsyncData(:final value) => ListView(
        children: [
          _VoiceBundleCard(states: value, onInstall: notifier.downloadBundle),
          // The technical parts (model names, quantization, voice engines)
          // live under Advanced; the primary surface stays plain words.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('voice-advanced'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                'Advanced',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                'Pick or remove individual voice models',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                for (final role in VoiceModelRole.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _roleLabel(role),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                  for (final s in value.where((s) => s.entry.role == role))
                    VoiceModelTile(
                      state: s,
                      onDownload: () => notifier.download(s.entry),
                      onDelete: () => notifier.delete(s.entry),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      AsyncError(:final error) => ErrorStateView(
        error: error,
        onRetry: () => ref.invalidate(voiceModelsControllerProvider),
      ),
      _ => const Center(child: DhruvaLoader()),
    };
  }

  String _roleLabel(VoiceModelRole role) => switch (role) {
    VoiceModelRole.vad => 'Knows when you stop talking (required)',
    VoiceModelRole.asr => 'Listens to you',
    VoiceModelRole.tts => 'Speaks the answers',
  };
}

/// WS5 "one guided step": the single primary action that installs everything
/// hands-free needs (VAD + ASR + a default voice) in one tap, with aggregate
/// progress — so a first-timer never has to understand the three roles below
/// or download them separately. The per-role tiles remain for adding extra
/// voices or re-downloading a single failed model.
class _VoiceBundleCard extends StatelessWidget {
  final List<VoiceModelState> states;
  final VoidCallback onInstall;

  const _VoiceBundleCard({required this.states, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final bundleIds = voiceBundleEntries.map((e) => e.id).toSet();
    final bundle = states.where((s) => bundleIds.contains(s.entry.id)).toList();
    final installed = bundle
        .where((s) => s.status == VoiceModelStatus.installed)
        .length;
    final active = bundle.any(
      (s) =>
          s.status == VoiceModelStatus.downloading ||
          s.status == VoiceModelStatus.installing,
    );
    final allInstalled = bundle.isNotEmpty && installed == bundle.length;
    // Aggregate progress: an installed model counts as done (1.0), an in-flight
    // one contributes its live fraction, everything else 0.
    final progress =
        bundle.fold<double>(0, (sum, s) {
          if (s.status == VoiceModelStatus.installed) return sum + 1;
          if (s.status == VoiceModelStatus.downloading) {
            return sum + s.progress;
          }
          return sum;
        }) /
        (bundle.isEmpty ? 1 : bundle.length);

    return Card(
      margin: EdgeInsets.all(tokens.spacing.md),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allInstalled ? Icons.check_circle : Icons.graphic_eq_outlined,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    'Talk hands-free',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              allInstalled
                  ? 'Everything you need to talk is installed. You\'re ready.'
                  : 'Talk to ${AppIdentity.shortName} and hear it answer, all on '
                        'your phone. One tap installs everything.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.md),
            if (allInstalled)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      SizedBox(width: tokens.spacing.xs),
                      Text('Voice ready', style: theme.textTheme.labelLarge),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  // WS5: installing the bundle used to dead-end here with no way
                  // to start talking. Point the user at the home's "Talk" entry.
                  // Nav only (no ChatController) so ADR-002 holds — features/
                  // models_hub can't launch a chat-backed voice session itself.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/ask'),
                      icon: const Icon(Icons.record_voice_over_outlined),
                      label: const Text('Go to Ask to talk'),
                    ),
                  ),
                ],
              )
            else if (active)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radius.full),
                    child: LinearProgressIndicator(value: progress),
                  ),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    'Installing… $installed of ${bundle.length} ready',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install voice bundle'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ModelAction { chat, delete }

class _InstalledTab extends ConsumerWidget {
  const _InstalledTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(storageControllerProvider);
    return switch (state) {
      AsyncData(:final value) => _InstalledBody(state: value),
      AsyncError(:final error) => ErrorStateView(
        error: error,
        onRetry: () => ref.read(storageControllerProvider.notifier).refresh(),
      ),
      _ => const Center(child: DhruvaLoader()),
    };
  }
}

class _InstalledBody extends ConsumerWidget {
  final StorageState state;
  const _InstalledBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(storageControllerProvider.notifier).refresh(),
      child: ListView(
        children: [
          // D11: a Wrap, not a Row, so on a narrow phone (or a big text scale)
          // the "N installed" line and the Import button stack with a
          // 16 px gutter instead of colliding.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  '${state.installed.length} installed · '
                  '${_formatBytes(state.totalBytes)} used',
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import a model file'),
                  onPressed: state.importingName != null
                      ? null
                      : () => _importFile(context, ref),
                ),
              ],
            ),
          ),
          if (state.installed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Test all speeds'),
                  onPressed: ref.watch(speedTestControllerProvider).active
                      ? null
                      : () => ref
                            .read(speedTestControllerProvider.notifier)
                            .run(state.installed),
                ),
              ),
            ),
          const SpeedTestStatusBar(),
          SpeedTestOfferBanner(installed: state.installed),
          if (state.importingName != null)
            _ImportProgress(
              name: state.importingName!,
              progress: state.importProgress,
              onCancel: () =>
                  ref.read(storageControllerProvider.notifier).cancelImport(),
            ),
          if (state.actionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                // The generic corrupt-file copy says "removed" (download
                // case); an import is rejected before anything is written.
                state.actionError is StorageCorruptFileFailure
                    ? "That isn't a GGUF model file — pick a .gguf exported "
                          'for llama.cpp.'
                    : friendlyFailureMessage(state.actionError!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (state.installed.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyStateView(
                message:
                    'No models installed yet. Pick one from Discover or import '
                    'a model file from your phone.',
                icon: Icons.folder_open,
              ),
            )
          else
            ...state.installed.map(
              (m) => ListTile(
                // WS1: a model downloaded from the curated Discover catalog must
                // NOT revert to its cryptic repo id here. Resolve the friendly
                // name from the starter catalog; fall back to the repo id for
                // models imported or found via advanced HF search.
                title: Text(
                  friendlyModelName(m.repoId),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plainQuantName(m.quant)} · ${_formatBytes(m.sizeBytes)}',
                    ),
                    SpeedTestRow(model: m),
                  ],
                ),
                // A LABELLED overflow instead of two bare icons side by side
                // (wave 4: "chat" and "trash" next to each other, unlabelled).
                // Chat carries the model (`extra: <drift row id>` →
                // ChatRouteArgs.initialModelId) so it opens a LOADED chat.
                trailing: PopupMenuButton<_ModelAction>(
                  key: ValueKey('installed-menu-${m.id}'),
                  tooltip: 'Model actions',
                  onSelected: (a) => switch (a) {
                    _ModelAction.chat => context.push('/chat/new', extra: m.id),
                    _ModelAction.delete => _confirmDelete(context, ref, m),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ModelAction.chat,
                      child: ListTile(
                        leading: Icon(Icons.chat_bubble_outline),
                        title: Text('Chat'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _ModelAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    InstalledModelInfo m,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
          'This removes ${m.fileName} (${_formatBytes(m.sizeBytes)}) from '
          'this device.',
        ),
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
    if (confirmed == true) {
      await ref.read(storageControllerProvider.notifier).delete(m.id);
    }
  }

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    const typeGroup = XTypeGroup(label: 'GGUF', extensions: ['gguf']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final notifier = ref.read(storageControllerProvider.notifier);
    if (await notifier.importExists(p.basename(picked.path))) {
      if (!context.mounted) return;
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Model already imported'),
          content: Text(
            '${p.basename(picked.path)} is already on this device. Replace '
            'it with the selected file?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    await notifier.importLocal(File(picked.path));
  }
}

/// Copy progress for a sideloaded GGUF — multi-GB files take a while, so the
/// user gets a determinate bar and a way out.
class _ImportProgress extends StatelessWidget {
  final String name;
  final double progress;
  final VoidCallback onCancel;
  const _ImportProgress({
    required this.name,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Importing $name · ${(progress * 100).round()}%',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel import',
            onPressed: onCancel,
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
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '$bytes B';
}
