/// Search files (`/library/search`): keyword search over the indexed folder.
/// Results show the file name, the passage that matched and its page; a tap
/// opens the file sheet (open in the OS viewer / ask about this file).
///
/// States: folder not connected (connect), nothing typed (hint), searching
/// (skeleton), no match (what to try), failure (retry).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/dhruva_sheet.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/search_index.dart';
import '../state/library_documents.dart';
import '../state/library_text.dart';
import '../widgets/file_sheet.dart';

/// Hits are deduplicated per file (a long file has several searchable
/// sections); the best section's passage is the one shown.
List<SearchHit> bestHitPerFile(List<SearchHit> hits) {
  final seen = <String>{};
  return [
    for (final h in hits)
      if (seen.add((h.item.flags['fileId'] as String?) ?? h.item.externalId)) h,
  ];
}

class FileSearchScreen extends ConsumerStatefulWidget {
  const FileSearchScreen({super.key});

  @override
  ConsumerState<FileSearchScreen> createState() => _FileSearchScreenState();
}

class _FileSearchScreenState extends ConsumerState<FileSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final folder = ref
        .watch(connectorListProvider)
        .value
        ?.where((e) => e.connector.id == ConnectorIds.folder)
        .firstOrNull;
    final connected = folder != null && folder.status.isConnected;

    Widget body;
    if (!connected) {
      body = _Message(
        title: 'Connect a folder to search it',
        body:
            'Pick one folder of notes or documents and search inside the files, '
            'right on this phone.',
        actionLabel: 'Open Connectors',
        actionKey: const ValueKey('search-connect'),
        onAction: () => context.push('/settings/connectors'),
      );
    } else if (_query.isEmpty) {
      body = const _Message(
        title: 'Search inside your files',
        body: 'Type a word or two. Text, Markdown and PDF files are searched.',
      );
    } else {
      final q = ConnectorSearchQuery(
        _query,
        sources: const {ConnectorIds.folder},
        kinds: const {ItemKind.file},
        limit: 40,
      );
      body = ref
          .watch(connectorSearchProvider(q))
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (e, _) => ErrorStateView(
              error: e,
              onRetry: () => ref.invalidate(connectorSearchProvider(q)),
            ),
            data: (hits) {
              final files = bestHitPerFile(hits);
              if (files.isEmpty) {
                return _Message(
                  title: 'No file matches "$_query"',
                  body:
                      'Try another word. Files still waiting to be indexed '
                      'are not searched yet; Index now in Connectors finishes '
                      'them.',
                  actionLabel: 'Open Connectors',
                  actionKey: const ValueKey('search-open-connectors'),
                  onAction: () => context.push('/settings/connectors'),
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  tokens.spacing.base,
                  tokens.spacing.sm,
                  tokens.spacing.base,
                  tokens.spacing.xl2,
                ),
                itemCount: files.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                itemBuilder: (context, i) =>
                    _HitRow(hit: files[i], query: _query),
              );
            },
          );
    }

    return ChromeScaffold(
      appBar: AdaptiveAppBar(
        title: TextField(
          key: const ValueKey('file-search-field'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (t) {
            _debounce?.cancel();
            setState(() => _query = t.trim());
          },
          decoration: const InputDecoration(
            hintText: 'Search files',
            border: InputBorder.none,
          ),
        ),
      ),
      bodyBuilder: (context, inset) => Padding(
        padding: EdgeInsets.only(top: inset.top, bottom: inset.bottom),
        child: body,
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.query});
  final SearchHit hit;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final item = hit.item;
    final snippet = snippetFor(item.body, query);
    final page = item.flags['page'];
    final paged = item.flags['pages'] != null && page is int;
    return InkWell(
      key: ValueKey('hit-${item.id}'),
      onTap: () => showDhruvaSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FileSheet(
          file: LibraryFile(
            fileId: (item.flags['fileId'] as String?) ?? item.externalId,
            name: item.title,
            itemId: item.id,
            pages: item.flags['pages'] as int?,
            modified: item.sentAt,
          ),
          snippet: snippet,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (paged)
                  Text(
                    'Page $page',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (snippet.isNotEmpty) ...[
              SizedBox(height: tokens.spacing.xs),
              Text(
                snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });
  final String title;
  final String body;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              SizedBox(height: tokens.spacing.base),
              FilledButton.tonal(
                key: actionKey,
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
