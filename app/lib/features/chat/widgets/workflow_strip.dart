/// "Quick workflows" strip on the conversation list: the handful of most useful
/// one-tap text verbs plus "All". Chips push `/workflows?id=<id>` (the router
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
          child: Text(
            'QUICK WORKFLOWS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
            children: [
              for (final (id, icon, label) in _quick) ...[
                ActionChip(
                  avatar: Icon(
                    icon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(label),
                  onPressed: () => context.push('/workflows?id=$id'),
                ),
                SizedBox(width: tokens.spacing.xs),
              ],
              ActionChip(
                label: const Text('All'),
                avatar: const Icon(Icons.arrow_forward_rounded, size: 16),
                onPressed: () => context.push('/workflows'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
