/// The "Search in" row above the Ask composer (comp `ask.png`): Auto · Mail ·
/// Calendar · Contacts · Files · Docs.
///
/// * Auto (default): rules pick sources from what is being typed; the ones it
///   picked show outlined so the choice is visible BEFORE sending.
/// * Tapping a source leaves Auto and pins that set (filled chips); tapping
///   Auto goes back. A pinned set of nothing means "just the model".
/// * A source the user has not connected shows "Connect" and opens that
///   connector's card instead of selecting (never a dead tap). Mail is hidden
///   until a mail connector exists.
///
/// Colors and text styles come from the theme; icons are ones the app already
/// ships (the tree-shaken icon font cannot gain glyphs via Shorebird).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/ask_sources.dart';

IconData askSourceIcon(AskSource s) => switch (s) {
  AskSource.mail => Icons.mail_outline,
  AskSource.calendar => Icons.calendar_today_outlined,
  AskSource.contacts => Icons.people_outline,
  AskSource.files => Icons.folder_outlined,
  AskSource.docs => Icons.description_outlined,
};

class SearchInChips extends StatelessWidget {
  const SearchInChips({
    super.key,
    required this.selection,
    required this.resolved,
    required this.chips,
    required this.onAuto,
    required this.onToggle,
    required this.onConnect,
  });

  final AskSourceSelection selection;

  /// What this question would search right now (Auto's pick, or the pinned
  /// set), limited to ready sources.
  final Set<AskSource> resolved;
  final List<({AskSource source, AskChipAvailability availability})> chips;
  final VoidCallback onAuto;
  final ValueChanged<AskSource> onToggle;
  final ValueChanged<AskSource> onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: tokens.spacing.xs),
          child: Text(
            'Search in',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            key: const ValueKey('search-in-chips'),
            scrollDirection: Axis.horizontal,
            children: [
              _SourceChip(
                chipKey: const ValueKey('search-in-auto'),
                icon: Icons.auto_awesome_outlined,
                label: 'Auto',
                state: selection.auto ? _ChipState.filled : _ChipState.idle,
                semantics: selection.auto
                    ? 'Auto, on. Picks sources from your question.'
                    : 'Auto, off. Tap to let the app pick sources.',
                onTap: onAuto,
              ),
              for (final c in chips)
                _SourceChip(
                  chipKey: ValueKey('search-in-${c.source.name}'),
                  icon: askSourceIcon(c.source),
                  label: c.source.label,
                  trailing: c.availability == AskChipAvailability.needsConnect
                      ? 'Connect'
                      : null,
                  state: c.availability == AskChipAvailability.needsConnect
                      ? _ChipState.connect
                      : !resolved.contains(c.source)
                      ? _ChipState.idle
                      : selection.auto
                      ? _ChipState.outlined
                      : _ChipState.filled,
                  semantics: c.availability == AskChipAvailability.needsConnect
                      ? '${c.source.label}, not connected. Opens its '
                            'connector.'
                      : resolved.contains(c.source)
                      ? '${c.source.label}, searched'
                      : '${c.source.label}, not searched',
                  onTap: () => c.availability == AskChipAvailability.ready
                      ? onToggle(c.source)
                      : onConnect(c.source),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ChipState {
  /// Pinned, or Auto itself while on.
  filled,

  /// Picked by Auto for this question.
  outlined,

  /// Not searched.
  idle,

  /// Not connected.
  connect,
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.chipKey,
    required this.icon,
    required this.label,
    required this.state,
    required this.semantics,
    required this.onTap,
    this.trailing,
  });

  final Key chipKey;
  final IconData icon;
  final String label;
  final String? trailing;
  final _ChipState state;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final (fill, border, fg) = switch (state) {
      _ChipState.filled => (
        scheme.primaryContainer,
        Colors.transparent,
        scheme.onPrimaryContainer,
      ),
      _ChipState.outlined => (
        Colors.transparent,
        scheme.primary,
        scheme.primary,
      ),
      _ChipState.idle || _ChipState.connect => (
        scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        scheme.outlineVariant,
        scheme.onSurfaceVariant,
      ),
    };
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : tokens.motion.fast;
    return Padding(
      padding: EdgeInsets.only(right: tokens.spacing.sm),
      child: Semantics(
        key: chipKey,
        button: true,
        selected: state == _ChipState.filled || state == _ChipState.outlined,
        label: semantics,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onTap,
          // The pill is 40 high; the row it sits in is 48, so the tap target
          // meets the 48 minimum.
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: tokens.motion.standard,
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(tokens.radius.full),
                border: Border.all(color: border, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: fg),
                  SizedBox(width: tokens.spacing.xs),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(color: fg),
                  ),
                  if (trailing != null) ...[
                    SizedBox(width: tokens.spacing.xs),
                    Text(
                      trailing!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
