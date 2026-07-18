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
    // Scroll-safe: with the value copy below, the content can exceed a short
    // viewport (small phones, split-screen). Centre it when it fits, scroll
    // when it doesn't — instead of a RenderFlex overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
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
                SizedBox(height: tokens.spacing.md),
                // Value made explicit (VIDEO_FIXES #6 / CLAUDE.md "real
                // value"): the concrete use case, then the brand tagline.
                Text(
                  'A private AI that runs entirely on your phone — chat, '
                  'analyze photos, and talk. Nothing is sent to any server.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: tokens.spacing.sm),
                Text(
                  'Your AI. Your phone. Nobody else\'s business.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontStyle: FontStyle.italic,
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
        ),
      ),
    );
  }
}

/// WS3: the empty state for a conversation that HAS a model loaded but no
/// messages yet. Instead of a dead "Say hello" placeholder, it offers a few
/// tappable starter prompts — one tap sends the prompt straight into chat, so
/// a first-time user sees a working reply without having to think of anything
/// to type (PRD golden path: "land in chat with suggested prompts → tap one").
class SuggestedPrompts extends StatelessWidget {
  /// Called with the prompt text when the user taps a starter. The screen
  /// wires this to `ChatController.sendMessage`.
  final ValueChanged<String> onSelect;
  const SuggestedPrompts({super.key, required this.onSelect});

  /// General-purpose, model-agnostic starters. Kept short and concrete so a
  /// small on-device model gives a satisfying first answer. First entry
  /// mirrors the website chat mockup verbatim.
  static const prompts = <_Starter>[
    _Starter(
      Icons.code_rounded,
      'Explain a stack in one line, then show a Dart example.',
    ),
    _Starter(Icons.auto_stories_outlined, 'Write a haiku about the ocean.'),
    _Starter(
      Icons.restaurant_outlined,
      'Give me 3 quick dinner ideas with chicken.',
    ),
    _Starter(Icons.lightbulb_outline, 'Explain how a rainbow forms, simply.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: DhruvaStar(size: 64, color: theme.colorScheme.primary)),
          SizedBox(height: tokens.spacing.md),
          Text(
            'Ready when you are',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'Ask anything, or tap a prompt to start.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'SUGGESTED',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          for (final starter in prompts) ...[
            _StarterCard(starter: starter, onTap: () => onSelect(starter.text)),
            SizedBox(height: tokens.spacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Starter {
  final IconData icon;
  final String text;
  const _Starter(this.icon, this.text);
}

class _StarterCard extends StatelessWidget {
  final _Starter starter;
  final VoidCallback onTap;
  const _StarterCard({required this.starter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: Row(
            children: [
              Icon(starter.icon, size: 18, color: theme.colorScheme.primary),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  starter.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Icon(
                Icons.north_east_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
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
