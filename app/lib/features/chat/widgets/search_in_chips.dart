/// Ask's sources control. The composer shows ONE chip ([SourcesChip], "Sources:
/// Auto"); tapping it opens a sheet with the toggles ([SearchInChips]): Auto ·
/// Mail · Calendar · Contacts · Files · Docs. The selection state itself is the
/// canonical `askSelectionProvider` (the same one `/ask/new` pins into).
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

/// What the one composer chip says: "Sources: Auto", the pinned sources, or
/// "Sources: None" (just the model). A thread that is ABOUT an item says so.
String sourcesChipLabel({
  required AskSourceSelection selection,
  required Set<AskSource> resolved,
  List<String> focusTitles = const [],
}) {
  if (focusTitles.isNotEmpty) {
    final more = focusTitles.length > 1 ? ' +${focusTitles.length - 1}' : '';
    return 'About: ${focusTitles.first}$more';
  }
  if (selection.auto) return 'Sources: Auto';
  final names = [
    for (final s in AskSource.values)
      if (resolved.contains(s)) s.label,
  ];
  if (names.isEmpty) return 'Sources: None';
  if (names.length <= 2) return 'Sources: ${names.join(', ')}';
  return 'Sources: ${names.first} +${names.length - 1}';
}

/// The single, never-clipped chip above the Ask composer's input. Opens the
/// sources sheet.
class SourcesChip extends StatelessWidget {
  const SourcesChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: '$label. Opens the list of sources to search.',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              height: 36,
              padding: EdgeInsets.only(
                left: tokens.spacing.md,
                right: tokens.spacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(tokens.radius.full),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 2 * 48,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                    SizedBox(width: tokens.spacing.xs),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The toggles inside the sources sheet: Auto, then one chip per source,
/// wrapping onto more lines instead of scrolling or clipping.
class SearchInChips extends StatelessWidget {
  const SearchInChips({
    super.key,
    required this.selection,
    required this.resolved,
    required this.chips,
    required this.onAuto,
    required this.onToggle,
    required this.onConnect,
    this.focusTitles = const [],
  });

  /// Titles of the items this thread is ABOUT (`/ask/new?focus=`): shown
  /// first as "About" chips, always on.
  final List<String> focusTitles;

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
    return Wrap(
      key: const ValueKey('search-in-chips'),
      runSpacing: 4,
      children: [
        for (var i = 0; i < focusTitles.length; i++)
          _SourceChip(
            chipKey: ValueKey('search-in-focus-$i'),
            icon: Icons.description_outlined,
            label: focusTitles[i],
            trailing: 'About',
            state: _ChipState.filled,
            semantics: 'About ${focusTitles[i]}. Always searched.',
          ),
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
                ? '${c.source.label}, not connected. Opens its connector.'
                : resolved.contains(c.source)
                ? '${c.source.label}, searched'
                : '${c.source.label}, not searched',
            onTap: () => c.availability == AskChipAvailability.ready
                ? onToggle(c.source)
                : onConnect(c.source),
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
    this.onTap,
    this.trailing,
  });

  final Key chipKey;
  final IconData icon;
  final String label;
  final String? trailing;
  final _ChipState state;
  final String semantics;

  /// Null: a label, not a control (the focus chip).
  final VoidCallback? onTap;

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
        button: onTap != null,
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: fg),
                    SizedBox(width: tokens.spacing.xs),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: fg),
                      ),
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
      ),
    );
  }
}
