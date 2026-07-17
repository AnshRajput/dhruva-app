/// Chat empty states (chat-spec.md §7).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import 'brand_motif.dart';

class NoModelInstalledView extends StatelessWidget {
  final VoidCallback onBrowseModels;
  const NoModelInstalledView({super.key, required this.onBrowseModels});

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
            DhruvaStar(size: 96, color: theme.colorScheme.primary),
            SizedBox(height: tokens.spacing.lg),
            Text(
              'No model installed yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Pick a model from Hugging Face to start chatting — fully '
              'offline once it\'s on your device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.lg),
            FilledButton(
              onPressed: onBrowseModels,
              child: const Text('Browse models'),
            ),
          ],
        ),
      ),
    );
  }
}

class NoConversationsView extends StatelessWidget {
  final VoidCallback onNewChat;
  const NoConversationsView({super.key, required this.onNewChat});

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
            DhruvaStar(size: 72, color: theme.colorScheme.primary),
            SizedBox(height: tokens.spacing.lg),
            Text(
              'Start your first conversation',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Your chats stay on this device — no account, no cloud, no '
              'one watching.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            TrustMark(style: theme.textTheme.bodyMedium),
            SizedBox(height: tokens.spacing.lg),
            FilledButton(onPressed: onNewChat, child: const Text('New chat')),
          ],
        ),
      ),
    );
  }
}
