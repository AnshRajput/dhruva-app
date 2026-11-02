/// "Quick actions" strip on the conversation list: the handful of most useful
/// one-tap text verbs plus "All". Chips push `/actions?id=<id>` (the router
/// opens that workflow's sheet) so `features/chat` never imports
/// `features/workflows` (ADR-002); the ids here mirror its catalog.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

class WorkflowStrip extends StatelessWidget {
  const WorkflowStrip({super.key});

  static const _quick = <(String, IconData, String)>[
    ('summarize', Icons.short_text_rounded, 'Summarize'),
    ('translate', Icons.translate_rounded, 'Translate'),
    ('rewrite', Icons.edit_note_rounded, 'Rewrite'),
    ('draft_reply', Icons.reply_rounded, 'Draft a reply'),
    ('document', Icons.description_outlined, 'Read a document'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.md,
            tokens.spacing.sm,
            tokens.spacing.md,
            tokens.spacing.xs,
          ),
          // Sentence case like every other section header (this one was the
          // only uppercase tracked label in the app).
          child: Text(
            'Quick actions',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Wraps instead of scrolling: no chip is ever clipped off the edge.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
          child: Wrap(
            spacing: tokens.spacing.xs,
            runSpacing: tokens.spacing.xs,
            children: [
              for (final (id, icon, label) in _quick)
                ActionChip(
                  avatar: Icon(
                    icon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(label),
                  onPressed: () => context.push('/actions?id=$id'),
                ),
              ActionChip(
                label: const Text('All actions'),
                avatar: const Icon(Icons.arrow_forward_rounded, size: 16),
                onPressed: () => context.push('/actions'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
