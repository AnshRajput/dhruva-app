/// The collapsible "Sources" row under a reply that was grounded in an
/// attached document: which pages the answer drew on, with a short snippet
/// of each so the user can check it. Collapsed by default, like
/// `reasoning_block.dart`.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/docs/grounding.dart';

class SourcesBlock extends StatefulWidget {
  final List<DocSource> sources;

  const SourcesBlock({super.key, required this.sources});

  @override
  State<SourcesBlock> createState() => _SourcesBlockState();
}

class _SourcesBlockState extends State<SourcesBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final sources = widget.sources;
    final multiDoc = sources.map((s) => s.docName).toSet().length > 1;
    // Reduced motion: no movement, the rows simply appear.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : tokens.motion.fast;
    final summary = sources.map((s) => s.label).join(', ');

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: 'Sources: $summary',
            excludeSemantics: true,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 16,
                          color: scheme.secondary,
                        ),
                        SizedBox(width: tokens.spacing.xs),
                        Flexible(
                          child: Text(
                            'Sources · $summary',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: tokens.spacing.xs),
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: duration,
                          curve: tokens.motion.standard,
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: scheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: tokens.motion.standard,
            alignment: Alignment.topLeft,
            child: _expanded
                ? Padding(
                    padding: EdgeInsets.only(top: tokens.spacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in sources)
                          Padding(
                            padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                            child: _SourceRow(source: s, showName: multiDoc),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final DocSource source;
  final bool showName;
  const _SourceRow({required this.source, required this.showName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(tokens.radius.full),
          ),
          child: Text(
            source.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: tokens.spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showName)
                Text(
                  source.docName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Text(
                source.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
