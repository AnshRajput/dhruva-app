/// "Sources" chips under a grounded Ask answer (comp `ask.png`): one chip per
/// item the answer cited, icon by kind, short label ("Ravi, Q4 budget",
/// "Mon 2 Nov, Design sync", a file name). Tapping opens the item
/// ([SourceDetailSheet]). Ungrounded answers render nothing.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/ask_sources.dart';
import '../../../data/connectors/connector.dart';

IconData itemKindIcon(ItemKind k) => switch (k) {
  ItemKind.mail => Icons.mail_outline,
  ItemKind.event => Icons.calendar_today_outlined,
  ItemKind.contact => Icons.people_outline,
  ItemKind.file => Icons.description_outlined,
  ItemKind.notification => Icons.notifications_none,
};

class AnswerSourceChips extends StatelessWidget {
  const AnswerSourceChips({
    super.key,
    required this.sources,
    required this.onOpen,
  });

  final List<ItemSource> sources;
  final ValueChanged<ItemSource> onOpen;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return Padding(
      key: const ValueKey('answer-sources'),
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sources',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          Wrap(
            spacing: tokens.spacing.sm,
            children: [
              for (final s in sources)
                Semantics(
                  button: true,
                  label: 'Source: ${s.label}. Opens details.',
                  excludeSemantics: true,
                  child: PressableScale(
                    onTap: () => onOpen(s),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Center(
                        widthFactor: 1,
                        child: Container(
                          key: ValueKey('source-chip-${s.itemId}'),
                          height: 40,
                          constraints: const BoxConstraints(maxWidth: 240),
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                            border: Border.all(color: scheme.outlineVariant),
                            borderRadius: BorderRadius.circular(
                              tokens.radius.full,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                itemKindIcon(s.kind),
                                size: 18,
                                color: scheme.primary,
                              ),
                              SizedBox(width: tokens.spacing.xs),
                              Flexible(
                                child: Text(
                                  s.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens one cited item. [item] is null when it no longer exists (deleted, or
/// that source was disconnected). Item text is shown as plain text only: it is
/// untrusted, so nothing in it is ever linked or acted on.
Future<void> showSourceSheet(
  BuildContext context, {
  required ItemSource source,
  required ConnectorItem? item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SourceDetailSheet(
      source: source,
      item: item,
      onOpenLibrary: () {
        Navigator.of(sheetContext).pop();
        // Chat threads sit outside the shell: `go`, never `push`, a tab.
        context.go('/library');
      },
    ),
  );
}

class SourceDetailSheet extends StatelessWidget {
  const SourceDetailSheet({
    super.key,
    required this.source,
    required this.item,
    required this.onOpenLibrary,
  });

  final ItemSource source;
  final ConnectorItem? item;
  final VoidCallback onOpenLibrary;

  static const _maxBodyChars = 1500;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final it = item;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return SingleChildScrollView(
      key: const ValueKey('source-sheet'),
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        0,
        tokens.spacing.base,
        tokens.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (it == null) ...[
            Text('No longer on this phone', style: theme.textTheme.titleLarge),
            SizedBox(height: tokens.spacing.sm),
            Text(
              '"${source.label}" was removed, or you disconnected that '
              'source. Answers keep their chips, but the item itself is gone.',
              style: muted,
            ),
          ] else ...[
            Row(
              children: [
                Icon(itemKindIcon(it.kind), size: 20, color: scheme.primary),
                SizedBox(width: tokens.spacing.sm),
                Text(_kindLabel(it), style: theme.textTheme.labelLarge),
              ],
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              it.title.isEmpty ? source.label : it.title,
              style: theme.textTheme.titleLarge,
            ),
            ..._details(context, it, muted),
            if (it.kind == ItemKind.file) ...[
              SizedBox(height: tokens.spacing.base),
              FilledButton.tonalIcon(
                key: const ValueKey('source-open-library'),
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Open Library'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _kindLabel(ConnectorItem it) => switch (it.kind) {
    ItemKind.mail => 'Mail',
    ItemKind.event => 'Calendar event',
    ItemKind.contact => 'Contact',
    ItemKind.file => 'File',
    ItemKind.notification =>
      it.flags['app'] is String ? it.flags['app'] as String : 'Notification',
  };

  List<Widget> _details(
    BuildContext context,
    ConnectorItem it,
    TextStyle? muted,
  ) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget line(String text) => Padding(
      padding: EdgeInsets.only(top: tokens.spacing.xs),
      child: Text(text, style: muted),
    );
    final when = itemWhenText(it);
    final out = <Widget>[if (when != null) line(when)];
    final location = it.flags['location'];
    if (location is String && location.trim().isNotEmpty) {
      out.add(line(location.trim()));
    }
    final people = [
      for (final p in it.people)
        [?p.name, ?p.email].where((s) => s.trim().isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).take(8).join(', ');
    if (people.isNotEmpty) out.add(line('With $people'));
    final body = (it.summary ?? it.body).trim();
    if (body.isNotEmpty) {
      final shown = body.length <= _maxBodyChars
          ? body
          : '${body.substring(0, _maxBodyChars).trimRight()}…';
      out.add(
        Padding(
          padding: EdgeInsets.only(top: tokens.spacing.md),
          child: Text(shown, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return out;
  }
}
