/// One conversation-list row (chat-spec.md §6.2): swipe-to-delete
/// (confirmed) + a menu for pin/rename/move-to-folder/delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/chat/chat_repository.dart';
import '../state/conversation_list_controller.dart';

enum _TileAction { pin, rename, move, delete }

/// Sentinel `moveToFolder` result meaning "explicitly move to no folder" —
/// distinct from a null result, which means the picker sheet was dismissed.
const _noFolderSentinel = -1;

class ConversationTile extends ConsumerWidget {
  final ConversationSummary conversation;
  final List<FolderInfo> folders;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.folders,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(conversationListControllerProvider.notifier);

    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => notifier.delete(conversation.id),
      child: ListTile(
        leading: conversation.pinned
            ? Icon(Icons.push_pin, size: 18, color: theme.colorScheme.primary)
            : const SizedBox(width: 18),
        title: Text(
          conversation.title.isEmpty
              ? 'Untitled conversation'
              : conversation.title,
          style: theme.textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _relativeTime(conversation.updatedAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<_TileAction>(
          onSelected: (action) => _handleAction(context, notifier, action),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _TileAction.pin,
              child: Text(conversation.pinned ? 'Unpin' : 'Pin'),
            ),
            const PopupMenuItem(
              value: _TileAction.rename,
              child: Text('Rename'),
            ),
            const PopupMenuItem(
              value: _TileAction.move,
              child: Text('Move to folder'),
            ),
            const PopupMenuItem(
              value: _TileAction.delete,
              child: Text('Delete'),
            ),
          ],
        ),
        onTap: () => context.push('/chat/${conversation.id}'),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text("This can't be undone."),
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
    return confirmed ?? false;
  }

  Future<void> _handleAction(
    BuildContext context,
    ConversationListController notifier,
    _TileAction action,
  ) async {
    switch (action) {
      case _TileAction.pin:
        await notifier.setPinned(conversation.id, !conversation.pinned);
      case _TileAction.rename:
        await _rename(context, notifier);
      case _TileAction.move:
        await _move(context, notifier);
      case _TileAction.delete:
        if (await _confirmDelete(context)) {
          await notifier.delete(conversation.id);
        }
    }
  }

  Future<void> _rename(
    BuildContext context,
    ConversationListController notifier,
  ) async {
    final ctrl = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (title != null && title.isNotEmpty) {
      await notifier.rename(conversation.id, title);
    }
  }

  Future<void> _move(
    BuildContext context,
    ConversationListController notifier,
  ) async {
    final folderId = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('No folder'),
              onTap: () => Navigator.pop(context, _noFolderSentinel),
            ),
            for (final folder in folders)
              ListTile(
                title: Text(folder.name),
                onTap: () => Navigator.pop(context, folder.id),
              ),
          ],
        ),
      ),
    );
    if (folderId == null) return;
    await notifier.moveToFolder(
      conversation.id,
      folderId == _noFolderSentinel ? null : folderId,
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
