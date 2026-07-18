/// "Search all of Hugging Face (advanced)" (PRD v0.3 WS1): the raw HF search,
/// demoted from the default Models experience to this explicitly-secondary
/// screen reached from the curated tab. Results are STRICTLY filtered to
/// mobile-runnable GGUF (`modelSearchControllerProvider` drops any repo whose
/// name encodes > ~4B params). The name-only filter can't catch a large repo
/// that encodes no param token, so the real per-device fit check runs at
/// download time: `ListingDownloadController.download` classifies the resolved
/// quant's footprint against the device's RAM tier and refuses a model too big
/// for this phone. One-tap download per row via `ModelListTile`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../state/failure_message.dart';
import '../state/model_search_controller.dart';
import '../widgets/failure_view.dart';
import '../widgets/model_list_tile.dart';

class AdvancedSearchScreen extends StatelessWidget {
  const AdvancedSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Hugging Face')),
      body: const _SearchBody(),
    );
  }
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody();

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
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
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    // mk-composer (mock.css): a soft pill on `surfaceVariant` with a hairline
    // outline — not a boxy outlined field.
    final pillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radius.full),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.md,
            tokens.spacing.md,
            tokens.spacing.md,
            tokens.spacing.xs,
          ),
          child: TextField(
            controller: _queryCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search GGUF models on Hugging Face',
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              isDense: true,
              border: pillBorder,
              enabledBorder: pillBorder,
              focusedBorder: pillBorder.copyWith(
                borderSide: BorderSide(color: theme.colorScheme.primary),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (query) =>
                ref.read(modelSearchControllerProvider.notifier).search(query),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          child: Row(
            children: [
              Icon(
                Icons.smartphone,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  'GGUF models only; very large ones are hidden. '
                  'Fit for your phone is checked before download.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
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
    if (state.items.isEmpty) {
      return EmptyStateView(
        message: state.query.isEmpty
            ? 'Search Hugging Face for a phone-runnable GGUF model.'
            : 'No phone-runnable models found. Try a different search.',
      );
    }
    return RefreshIndicator(
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
            onTap: () =>
                context.push('/models/repo/${Uri.encodeComponent(model.id)}'),
          );
        },
      ),
    );
  }
}
