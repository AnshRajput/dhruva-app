/// The ONE trailing control for an installed model: a labelled overflow
/// (Chat / Delete, with a delete confirmation) instead of bare unlabelled
/// icons. Shared by the Installed tab, Discover cards, search rows and the
/// voice model tiles so an installed model looks and behaves the same
/// everywhere.
library;

import 'package:flutter/material.dart';

class InstalledModelMenu extends StatelessWidget {
  /// Null hides the Chat entry (voice bundles have nothing to chat with).
  final VoidCallback? onChat;
  final VoidCallback onDelete;

  /// Body of the "Delete model?" confirmation.
  final String deleteMessage;

  const InstalledModelMenu({
    super.key,
    this.onChat,
    required this.onDelete,
    required this.deleteMessage,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Model actions',
      onSelected: (isChat) async {
        if (isChat) return onChat?.call();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete model?'),
            content: Text(deleteMessage),
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
        if (confirmed == true) onDelete();
      },
      itemBuilder: (context) => [
        if (onChat != null)
          const PopupMenuItem(
            value: true,
            child: ListTile(
              leading: Icon(Icons.chat_bubble_outline),
              title: Text('Chat'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: false,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
