/// Models hub home (T5 §1-2, §5): search + installed as tabs, downloads
/// reachable from the app bar. One of the two bottom-nav destinations as of
/// Loop 4 (see `core/router/app_shell.dart`) — `/chat` is app home now.
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
import '../state/model_search_controller.dart';
import '../state/storage_controller.dart';
import '../state/voice_models_controller.dart';
import '../widgets/failure_view.dart';
import '../widgets/model_list_tile.dart';
import '../widgets/recommended_rail.dart';
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
              Tab(text: 'Search'),
              Tab(text: 'Installed'),
              Tab(text: 'Voice'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_SearchTab(), _InstalledTab(), _VoiceTab()],
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

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _queryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(modelSearchControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelSearchControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _queryCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search GGUF models on Hugging Face',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (query) =>
                ref.read(modelSearchControllerProvider.notifier).search(query),
          ),
        ),
        Expanded(
          child: switch (state) {
            AsyncData(:final value) => _ResultsList(
              state: value,
              scrollCtrl: _scrollCtrl,
            ),
            AsyncError(:final error) => ErrorStateView(
              error: error,
              onRetry: () => ref
                  .read(modelSearchControllerProvider.notifier)
                  .search(_queryCtrl.text),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }
}

class _ResultsList extends ConsumerWidget {
  final ModelSearchState state;
  final ScrollController scrollCtrl;
  const _ResultsList({required this.state, required this.scrollCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Amendment 4c: the recommended rail only makes sense above an
    // *unfiltered* view — once the user has typed a query, they've told us
    // what they want, so it stays out of the way of real search results.
    final showRail = state.query.isEmpty;

    if (state.items.isEmpty) {
      return Column(
        children: [
          if (showRail) const RecommendedRail(),
          Expanded(
            child: EmptyStateView(
              message: showRail
                  ? 'Try one of the recommended picks above, or search '
                        'Hugging Face for something specific.'
                  : 'No models found. Try a different search.',
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (showRail) const RecommendedRail(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(modelSearchControllerProvider.notifier).refresh(),
            child: ListView.separated(
              controller: scrollCtrl,
              itemCount: state.items.length + (state.hasMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i >= state.items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: state.loadMoreError != null
                          ? TextButton(
                              onPressed: () => ref
                                  .read(modelSearchControllerProvider.notifier)
                                  .loadMore(),
                              child: Text(
                                '${describeError(state.loadMoreError!)} · Tap to retry',
                              ),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  );
                }
                final model = state.items[i];
                return ModelListTile(
                  model: model,
                  onTap: () => context.push(
                    '/models/repo/${Uri.encodeComponent(model.id)}',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
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
                    'No models installed yet. Search Hugging Face or import '
                    'a local GGUF.',
                icon: Icons.folder_open,
              ),
            )
          else
            ...state.installed.map(
              (m) => ListTile(
                title: Text(m.repoId, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${m.fileName} · ${_formatBytes(m.sizeBytes)}'
                  '${m.quant != null ? ' · ${m.quant}' : ''}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, ref, m),
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
