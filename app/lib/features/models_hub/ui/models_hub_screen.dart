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

import '../../../data/downloads/storage_manager.dart';
import '../../../voice/voice_model_catalog.dart' show VoiceModelRole;
import '../state/failure_message.dart';
import '../state/recommended_models_provider.dart';
import '../state/storage_controller.dart';
import '../state/voice_models_controller.dart';
import '../widgets/curated_tab.dart';
import '../widgets/failure_view.dart';
import '../widgets/voice_model_tile.dart';

class ModelsHubScreen extends StatelessWidget {
  const ModelsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Models'),
          actions: [
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
          for (final role in VoiceModelRole.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                _roleLabel(role),
                style: Theme.of(context).textTheme.labelLarge,
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
      AsyncError(:final error) => ErrorStateView(
        error: error,
        onRetry: () => ref.invalidate(voiceModelsControllerProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  String _roleLabel(VoiceModelRole role) => switch (role) {
    VoiceModelRole.vad => 'Turn-taking (required)',
    VoiceModelRole.asr => 'Speech-to-text',
    VoiceModelRole.tts => 'Text-to-speech voices',
  };
}

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
      _ => const Center(child: CircularProgressIndicator()),
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${state.installed.length} installed · '
                  '${_formatBytes(state.totalBytes)} used',
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import GGUF'),
                  onPressed: () => _importFile(ref),
                ),
              ],
            ),
          ),
          if (state.actionError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                friendlyFailureMessage(state.actionError!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (state.installed.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyStateView(
                message:
                    'No models installed yet. Pick one from Discover or import '
                    'a local GGUF.',
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
                subtitle: Text(
                  '${m.quant ?? m.fileName} · ${_formatBytes(m.sizeBytes)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Designer Phase B nit: the Installed tab was delete-only.
                    // Add Chat (consistent with the Search tab's installed row)
                    // carrying the model — `extra: <drift row id>` →
                    // ChatRouteArgs.initialModelId — so it opens a LOADED chat.
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline),
                      tooltip: 'Chat',
                      onPressed: () => context.push('/chat/new', extra: m.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, ref, m),
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

  Future<void> _importFile(WidgetRef ref) async {
    const typeGroup = XTypeGroup(label: 'GGUF', extensions: ['gguf']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    await ref
        .read(storageControllerProvider.notifier)
        .importLocal(File(picked.path));
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
