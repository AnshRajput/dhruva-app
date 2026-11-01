/// The sheet for one file of the connected folder: open it in the phone's own
/// viewer, or ask about it (a new chat with the file as its source). Both are
/// user taps; nothing opens or asks by itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_sources.dart';
import '../state/library_documents.dart';
import '../state/library_text.dart';

Future<void> showFileSheet(BuildContext context, LibraryFile file) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FileSheet(file: file),
    );

class FileSheet extends ConsumerWidget {
  const FileSheet({super.key, required this.file, this.snippet});
  final LibraryFile file;

  /// The matching passage when opened from a search hit.
  final String? snippet;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final account = await ref
        .read(connectorStoreProvider)
        .account(ConnectorIds.folder);
    final grant = account?.config['grantId'];
    if (grant is! String) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The folder is not connected. Choose it in Connectors.',
          ),
        ),
      );
      return;
    }
    try {
      await ref.read(externalOpenerProvider).openFile(grant, file.fileId);
    } on OpenFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final sections = await ref
        .read(connectorStoreProvider)
        .fileSections(file.fileId);
    final ids = sections.isEmpty
        ? [file.itemId]
        : [for (final s in sections) s.id];
    navigator.pop();
    unawaited(
      router.push(
        Uri(
          path: '/chat/new',
          queryParameters: {
            'source': [for (final i in ids) '$i'],
          },
        ).toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final problem = file.problem;
    final facts = [
      if (file.pages != null) '${file.pages} pages',
      if (file.modified != null)
        'changed ${changedAgo(file.modified!, DateTime.now())}',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        0,
        tokens.spacing.base,
        tokens.spacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.name, style: theme.textTheme.titleLarge),
          if (facts.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.xs),
            Text(
              facts,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (snippet != null && snippet!.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.md),
            Text(snippet!, style: theme.textTheme.bodyMedium),
          ],
          if (problem != null) ...[
            SizedBox(height: tokens.spacing.md),
            Text(
              '${unreadableReason(problem)}, so it is not searchable and '
              'cannot be asked about. You can still open it.',
              key: const ValueKey('file-problem'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          SizedBox(height: tokens.spacing.base),
          Wrap(
            spacing: tokens.spacing.sm,
            runSpacing: tokens.spacing.sm,
            children: [
              FilledButton(
                key: const ValueKey('file-ask'),
                onPressed: problem == null ? () => _ask(context, ref) : null,
                child: const Text('Ask about this file'),
              ),
              OutlinedButton(
                key: const ValueKey('file-open'),
                onPressed: () => _open(context, ref),
                child: const Text('Open file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
