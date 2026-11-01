/// The Library's three lists: Documents, To-dos, Saved. Each is a header
/// ("See all" where there is more), rows, and a real empty state with a next
/// step. Loading shows quiet skeleton rows; a failed load names a retry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/library_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../data/library/library_store.dart';
import '../state/library_documents.dart';
import '../state/library_text.dart';
import 'file_sheet.dart';
import 'saved_sheet.dart';

/// Documents shown on the Library before "See all".
const documentsPreview = 4;
const savedPreview = 3;

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onSeeAll,
    this.seeAllKey,
  });
  final String title;
  final String? trailing;
  final VoidCallback? onSeeAll;
  final Key? seeAllKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        top: tokens.spacing.lg,
        bottom: tokens.spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (onSeeAll != null)
            TextButton(
              key: seeAllKey,
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
    );
    return Semantics(
      label: 'Loading',
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
              child: Row(
                children: [
                  bar(48, 48),
                  SizedBox(width: tokens.spacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(180, 14),
                      SizedBox(height: tokens.spacing.sm),
                      bar(120, 12),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---- documents ----------------------------------------------------------------

class DocumentRow extends StatelessWidget {
  const DocumentRow({super.key, required this.entry});
  final LibraryDocEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return InkWell(
      onTap: () {
        final chat = entry.conversationId;
        if (chat != null) {
          context.push('/chat/$chat');
        } else if (entry.file != null) {
          showFileSheet(context, entry.file!);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(tokens.radius.md),
              ),
              child: Text(
                entry.badge,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    entry.detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentsSection extends ConsumerWidget {
  const DocumentsSection({super.key, this.all = false});

  /// True on the full list: no preview cap, no header.
  final bool all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(libraryDocumentsProvider);
    final entries = docs.value;
    final body = docs.when(
      loading: () => const _SkeletonRows(),
      error: (e, _) => ErrorStateView(
        error: e,
        onRetry: () => ref.invalidate(allDocumentsProvider),
      ),
      data: (list) => list.isEmpty
          ? NextStepCard(
              icon: Icons.description_outlined,
              title: 'No documents yet',
              body:
                  'Attach a PDF or text file in Ask and your phone reads it '
                  'for you. Documents you attach are kept here, and so are the '
                  'files of a connected folder.',
              actionLabel: 'Read a document',
              actionKey: const ValueKey('library-documents-action'),
              onAction: () => context.push('/actions?id=document'),
            )
          : Column(
              children: [
                for (final e in all ? list : list.take(documentsPreview))
                  DocumentRow(key: ValueKey(e.key), entry: e),
              ],
            ),
    );
    if (all) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Documents',
          onSeeAll: (entries?.length ?? 0) > documentsPreview
              ? () => context.push('/library/documents')
              : null,
          seeAllKey: const ValueKey('library-documents-see-all'),
        ),
        body,
      ],
    );
  }
}

// ---- to-dos -------------------------------------------------------------------

class TodoRow extends ConsumerWidget {
  const TodoRow({super.key, required this.todo});
  final TodoItem todo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final store = ref.read(libraryStoreProvider);
    return Row(
      children: [
        Semantics(
          checked: todo.done,
          label: todo.text,
          child: IconButton(
            key: ValueKey('todo-check-${todo.id}'),
            tooltip: todo.done ? 'Mark as not done' : 'Mark as done',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => store.setTodoDone(todo.id, !todo.done),
            icon: Icon(
              todo.done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: todo.done
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
            child: Text(
              todo.text,
              style: theme.textTheme.bodyLarge?.copyWith(
                decoration: todo.done ? TextDecoration.lineThrough : null,
                color: todo.done ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ),
        IconButton(
          key: ValueKey('todo-delete-${todo.id}'),
          tooltip: 'Delete to-do',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => store.deleteTodo(todo.id),
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class TodosSection extends ConsumerWidget {
  const TodosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final todos = ref.watch(todosProvider);
    final list = todos.value;
    final open = list?.where((t) => !t.done).length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'To-dos',
          trailing: list == null || list.isEmpty ? null : '$open open',
        ),
        todos.when(
          loading: () => const _SkeletonRows(),
          error: (e, _) => ErrorStateView(
            error: e,
            onRetry: () => ref.invalidate(todosProvider),
          ),
          data: (list) => list.isEmpty
              ? NextStepCard(
                  icon: Icons.checklist_rounded,
                  title: 'No to-dos yet',
                  body:
                      'Run "Extract to-dos" on any text, then tap the checklist '
                      'button under the reply. The tasks collect here to '
                      'check off.',
                  actionLabel: 'Extract to-dos',
                  actionKey: const ValueKey('library-todos-action'),
                  onAction: () => context.push('/actions?id=todos'),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(tokens.radius.xl),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
                    child: Column(
                      children: [
                        for (final t in list)
                          TodoRow(key: ValueKey('todo-${t.id}'), todo: t),
                        if (list.any((t) => t.done))
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const ValueKey('todos-clear-done'),
                              onPressed: ref
                                  .read(libraryStoreProvider)
                                  .clearDoneTodos,
                              child: const Text('Clear done'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ---- saved --------------------------------------------------------------------

class SavedRow extends StatelessWidget {
  const SavedRow({super.key, required this.saved});
  final SavedAnswer saved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return InkWell(
      onTap: () => showSavedSheet(context, saved),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(tokens.radius.md),
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    saved.headline,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Saved ${changedAgo(saved.createdAt, DateTime.now())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedSection extends ConsumerWidget {
  const SavedSection({super.key, this.all = false});
  final bool all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedAnswersProvider);
    final body = saved.when(
      loading: () => const _SkeletonRows(),
      error: (e, _) => ErrorStateView(
        error: e,
        onRetry: () => ref.invalidate(savedAnswersProvider),
      ),
      data: (list) => list.isEmpty
          ? NextStepCard(
              icon: Icons.bookmark_border_rounded,
              title: 'Nothing saved yet',
              body:
                  'Ask something, then tap the bookmark under a good answer or '
                  'draft. It will be waiting here.',
              actionLabel: 'Go to Ask',
              actionKey: const ValueKey('library-saved-action'),
              onAction: () => context.go('/ask'),
            )
          : Column(
              children: [
                for (final s in all ? list : list.take(savedPreview))
                  SavedRow(key: ValueKey('saved-${s.id}'), saved: s),
              ],
            ),
    );
    if (all) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Saved',
          onSeeAll: (saved.value?.length ?? 0) > savedPreview
              ? () => context.push('/library/saved')
              : null,
          seeAllKey: const ValueKey('library-saved-see-all'),
        ),
        body,
      ],
    );
  }
}
