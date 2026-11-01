/// "Clear all chat history" with the two confirmations, now on Settings >
/// Privacy (it is the user's stored data). Moved verbatim from the old
/// Settings list; behaviour unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import 'settings_widgets.dart';

class ClearHistoryRow extends ConsumerWidget {
  const ClearHistoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsRow(
      icon: Icons.delete_sweep_outlined,
      title: 'Clear all chat history',
      subtitle: 'Deletes every conversation and message',
      destructive: true,
      onTap: () => _clearAllHistory(context, ref),
    );
  }

  Future<void> _clearAllHistory(BuildContext context, WidgetRef ref) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all chat history?'),
        content: const Text(
          'This permanently deletes every conversation and message on '
          'this device. Downloaded models are NOT affected — they stay '
          'installed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          "This can't be undone — all conversations and messages will be "
          'gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all history'),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !context.mounted) return;

    await ref.read(chatRepositoryProvider).clearAllHistory();
    // UX-hardening A2: refresh the kept-alive Chat list immediately (no more
    // "pull to refresh" instruction) via the shared revision signal — settings
    // can't import `features/chat`'s controller (ADR-002).
    ref.read(conversationListRevisionProvider.notifier).bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chat history cleared.')));
  }
}
