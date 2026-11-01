/// One saved reply, in full: read it, copy it, open the chat it came from, or
/// delete it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/library_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/library/library_store.dart';

Future<void> showSavedSheet(BuildContext context, SavedAnswer saved) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SavedSheet(saved: saved),
    );

class SavedSheet extends ConsumerWidget {
  const SavedSheet({super.key, required this.saved});
  final SavedAnswer saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        0,
        tokens.spacing.base,
        tokens.spacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                saved.content,
                key: const ValueKey('saved-content'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.base),
          Wrap(
            spacing: tokens.spacing.sm,
            runSpacing: tokens.spacing.sm,
            children: [
              FilledButton(
                key: const ValueKey('saved-copy'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: saved.content));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Copied.')),
                  );
                },
                child: const Text('Copy'),
              ),
              if (saved.conversationId != null)
                OutlinedButton(
                  key: const ValueKey('saved-open-chat'),
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push('/chat/${saved.conversationId}');
                  },
                  child: const Text('Open chat'),
                ),
              TextButton(
                key: const ValueKey('saved-delete'),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await ref.read(libraryStoreProvider).deleteSaved(saved.id);
                  navigator.pop();
                },
                child: Text(
                  'Delete',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
