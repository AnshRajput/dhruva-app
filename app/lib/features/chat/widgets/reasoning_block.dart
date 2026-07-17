/// `<think>` block rendering (chat-spec.md §4). Collapsed by default,
/// always — even mid-stream (no auto-expand for a verbose reasoning model).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

class ReasoningBlock extends StatefulWidget {
  final String reasoning;

  /// True while the `<think>` tag is still open (streaming, no duration
  /// yet) — header reads "Reasoning…" instead of a wall-clock duration.
  final bool isOpen;
  final int? durationMs;

  const ReasoningBlock({
    super.key,
    required this.reasoning,
    required this.isOpen,
    this.durationMs,
  });

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;
    final label = widget.isOpen
        ? 'Reasoning…'
        : (widget.durationMs != null
              ? 'Reasoning (${(widget.durationMs! / 1000).round()}s)'
              : 'Reasoning');

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: tokens.motion.fast,
                    curve: tokens.motion.standard,
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: tokens.spacing.xs),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: tokens.motion.moderate,
            curve: tokens.motion.standard,
            alignment: Alignment.topLeft,
            child: _expanded
                ? Container(
                    padding: EdgeInsets.only(left: tokens.spacing.sm),
                    margin: EdgeInsets.only(bottom: tokens.spacing.xs),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: tokens.spacing.xs,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.reasoning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurfaceVariant,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}
