/// The connected-folder block at the top of the Library (comp: library.png):
/// folder name, index progress in plain words, Search files, Change folder.
/// Not connected: one row that opens the system folder picker. Needs
/// attention (folder gone, access lost): the reason and the fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/folder_index_status.dart';

class FolderBlock extends ConsumerWidget {
  const FolderBlock({super.key});

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await ref.read(connectorActionsProvider).chooseFolder();
      if (status.state == ConnectorState.needsAttention &&
          status.detail != null) {
        messenger.showSnackBar(SnackBar(content: Text(status.detail!)));
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't open the folder picker. Try again, or check that "
            'the file manager is enabled in system settings.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final entry = ref
        .watch(connectorListProvider)
        .value
        ?.where((e) => e.connector.id == ConnectorIds.folder)
        .firstOrNull;
    final status = entry?.status ?? ConnectorStatus.notConnected;

    if (status.state == ConnectorState.notConnected ||
        status.state == ConnectorState.unsupported) {
      return PressableScale(
        onTap: () => _choose(context, ref),
        semanticLabel: 'Connect a folder',
        child: DecoratedBox(
          key: const ValueKey('library-connect-folder'),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(tokens.radius.xl),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.base),
            child: Row(
              children: [
                _Tile(color: theme.colorScheme.primary),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect a folder',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Search your notes and files, right on this phone. '
                        'You pick one folder; nothing is uploaded.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final files = ref.watch(folderFilesProvider).value ?? const [];
    final account = ref
        .watch(connectorAccountsProvider)
        .value
        ?.where((a) => a.connector == ConnectorIds.folder)
        .firstOrNull;
    final index = FolderIndexStatus.of(
      files,
      total: account?.config['total'] as int?,
    );
    final indexing = status.state == ConnectorState.syncing;
    final needsFix = status.state == ConnectorState.needsAttention;

    return DecoratedBox(
      key: const ValueKey('library-folder-block'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Tile(color: theme.colorScheme.primary),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account?.label ?? 'Notes folder',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Connected folder',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            if (needsFix)
              Text(
                status.detail ?? 'The folder needs your attention.',
                key: const ValueKey('library-folder-problem'),
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.full),
                child: LinearProgressIndicator(
                  value: index.fraction ?? (indexing ? null : 0),
                  minHeight: 6,
                ),
              ),
              SizedBox(height: tokens.spacing.sm),
              Wrap(
                spacing: tokens.spacing.md,
                children: [
                  Text(
                    index.headline(),
                    key: const ValueKey('library-index-status'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    index.detail(indexing: indexing),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: tokens.spacing.md),
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.sm,
              children: [
                if (!needsFix)
                  FilledButton.icon(
                    key: const ValueKey('library-search-files'),
                    onPressed: () => context.push('/library/search'),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('Search files'),
                  ),
                OutlinedButton(
                  key: const ValueKey('library-change-folder'),
                  onPressed: indexing ? null : () => _choose(context, ref),
                  child: Text(needsFix ? 'Choose again' : 'Change folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Icon(Icons.folder_outlined, color: color),
    );
  }
}
