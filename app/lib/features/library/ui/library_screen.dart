/// Library: your documents, saved answers and to-dos, plus a connected folder.
/// Wave 1 ships real empty states that teach the next step; each ends in an
/// action that works today (Actions, Ask) or the connect placeholder.
/// Library is never "empty": the three sections are always there.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../core/widgets/pressable_scale.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget header(String t) => Padding(
      padding: EdgeInsets.only(
        top: tokens.spacing.lg,
        bottom: tokens.spacing.sm,
      ),
      child: Text(t, style: theme.textTheme.titleLarge),
    );

    return ChromeScaffold(
      appBar: const AdaptiveAppBar(
        title: Text('Library'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.base,
          tokens.spacing.xs,
          tokens.spacing.base,
          tokens.spacing.xl2,
        ),
        children: [
          const _FolderRow(),
          header('Documents'),
          NextStepCard(
            icon: Icons.description_outlined,
            title: 'No documents yet',
            body:
                'Open a document in Actions and your phone reads it for you. '
                'Documents you attach in Ask will be kept here.',
            actionLabel: 'Read a document',
            actionKey: const ValueKey('library-documents-action'),
            onAction: () => context.push('/actions?id=document'),
          ),
          header('Saved'),
          NextStepCard(
            icon: Icons.bookmark_border_rounded,
            title: 'Nothing saved yet',
            body:
                'Ask something, then save a good answer or draft. It will be '
                'waiting here.',
            actionLabel: 'Go to Ask',
            actionKey: const ValueKey('library-saved-action'),
            onAction: () => context.go('/ask'),
          ),
          header('To-dos'),
          NextStepCard(
            icon: Icons.checklist_rounded,
            title: 'No to-dos yet',
            body:
                'Run "Extract to-dos" on any text and the tasks it finds '
                'collect here to check off.',
            actionLabel: 'Extract to-dos',
            actionKey: const ValueKey('library-todos-action'),
            onAction: () => context.push('/actions?id=todos'),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return PressableScale(
      onTap: () => context.push('/settings/connectors'),
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
              Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
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
                      'Search your notes and files, right on this phone.',
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
}
