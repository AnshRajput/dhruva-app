/// Settings > Connectors (`/settings/connectors`), matching the approved
/// connectors comp: one row per available connector with its state, what it
/// can read in plain words and the one button that fits (Connect / Reconnect /
/// Turn on); a connector that needs the user is promoted to its own card with
/// the reason and the fix. Tapping a connected row opens its sheet (folder
/// index, notification apps, Disconnect). Below: the privacy ledger.
///
/// Gmail is listed only in a build that has OAuth client ids (otherwise its
/// connector is `unsupported` and hidden). Beta: in Google's Testing mode the
/// sign-in expires every 7 days, which reads as Needs attention + "Reconnect
/// Gmail".
///
/// States handled: loading (skeleton rows), nothing available, not connected,
/// connected, syncing, needs attention (reason + fix), permission denied
/// (Open settings). Nothing here is networked; "offline" does not apply.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/format/when.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/label_chip.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';
import '../state/connector_copy.dart';
import '../widgets/connector_sheet.dart';
import '../widgets/ledger_widgets.dart';
import '../widgets/settings_widgets.dart';

class ConnectorsScreen extends ConsumerWidget {
  const ConnectorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final entries = ref.watch(connectorListProvider);
    final list = entries.value;

    final fix = [
      for (final e in list ?? const <ConnectorEntry>[])
        if (needsFix(e.status)) e,
    ];
    final rest = [
      for (final e in list ?? const <ConnectorEntry>[])
        if (!needsFix(e.status)) e,
    ];

    return SettingsPage(
      title: 'Connectors',
      subtitle: 'Choose what ${AppIdentity.shortName} can read.',
      children: [
        if (list == null)
          const _Skeleton()
        else if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
            child: const _NothingAvailable(),
          )
        else ...[
          for (final e in fix)
            Padding(
              padding: EdgeInsets.only(
                left: tokens.spacing.base,
                right: tokens.spacing.base,
                bottom: tokens.spacing.md,
              ),
              child: _AttentionCard(entry: e),
            ),
          if (rest.isNotEmpty)
            SettingsGroup(
              children: [for (final e in rest) _ConnectorRow(entry: e)],
            ),
        ],
        const SizedBox(height: 8),
        const LedgerSection(),
      ],
    );
  }
}

// ---- rows ---------------------------------------------------------------------

/// Status dot + text. Colour comes from the theme, never from the label.
class StatusText extends StatelessWidget {
  const StatusText(this.line, {super.key});
  final StatusLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = switch (line.tone) {
      StatusTone.ok => tokens.success,
      StatusTone.attention => tokens.warning,
      StatusTone.off => theme.colorScheme.onSurfaceVariant,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: tokens.spacing.sm),
        Flexible(
          child: Text(
            line.label,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

String _whenText(BuildContext context, DateTime at) =>
    shortWhen(at, DateTime.now(), (d) => clockText(context, d));

class _ConnectorRow extends ConsumerStatefulWidget {
  const _ConnectorRow({required this.entry});
  final ConnectorEntry entry;

  @override
  ConsumerState<_ConnectorRow> createState() => _ConnectorRowState();
}

class _ConnectorRowState extends ConsumerState<_ConnectorRow> {
  bool _working = false;

  /// Where the last tap on the action ended when the system permission was
  /// not granted: the sentence to show inline, and whether the only way on is
  /// system settings. Null after a grant, or before the first tap.
  ConnectorStatus? _denied;

  Future<void> _connect() async {
    setState(() => _working = true);
    try {
      final s = await ref
          .read(connectorActionsProvider)
          .connect(widget.entry.connector.id);
      if (mounted) {
        setState(() {
          _denied = s.state == ConnectorState.notConnected && s.detail != null
              ? s
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Blocked for good: system settings is the way forward. Coming back with
  /// the permission on connects by itself (`ConnectorHub.onResume`).
  Future<void> _openSettings() => ref
      .read(connectorActionsProvider)
      .openSystemSettings(widget.entry.connector.id);

  @override
  Widget build(BuildContext context) {
    final c = widget.entry.connector;
    final status = widget.entry.status;
    final copy = copyFor(c.id);
    final connected = status.isConnected;
    final line = statusLine(status, when: (d) => _whenText(context, d));
    final denied = status.state == ConnectorState.notConnected ? _denied : null;
    final blocked = denied?.needsSettings ?? false;

    final action = FilledButton.tonal(
      key: ValueKey('connector-${c.id}-action'),
      onPressed: _working ? null : (blocked ? _openSettings : _connect),
      child: Text(blocked ? 'Open settings' : copy.connectLabel),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // On a narrow phone (360dp) a trailing button leaves the text column
        // ~160dp: the action drops under the text instead.
        final narrow = box.maxWidth < 420;
        final trailing = connected
            ? const Icon(Icons.chevron_right, size: 20)
            : (narrow ? null : action);
        return _body(
          context,
          copy: copy,
          line: line,
          trailing: trailing,
          below: !connected && narrow ? action : null,
          feedback: denied?.detail,
        );
      },
    );
  }

  Widget _body(
    BuildContext context, {
    required ConnectorCopy copy,
    required StatusLine line,
    required Widget? trailing,
    required Widget? below,
    String? feedback,
  }) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final c = widget.entry.connector;
    final connected = widget.entry.status.isConnected;
    return InkWell(
      key: ValueKey('connector-${c.id}'),
      onTap: connected
          ? () => showConnectorSheet(context, connectorId: c.id)
          : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.base,
          vertical: tokens.spacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsIconTile(copy.icon),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wrap: the chip drops to its own line before a name can break
                  // mid-word.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: tokens.spacing.sm,
                    runSpacing: tokens.spacing.xs,
                    children: [
                      Text(copy.name, style: theme.textTheme.titleMedium),
                      if (c.id == ConnectorIds.notifications)
                        const LabelChip('Android'),
                      if (c.id == ConnectorIds.mail) const LabelChip('Beta'),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.xs),
                  StatusText(line),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    copy.reads,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (feedback != null) ...[
                    SizedBox(height: tokens.spacing.sm),
                    // Announced to screen readers the moment it appears.
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        feedback,
                        key: ValueKey('connector-${c.id}-feedback'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.warning,
                        ),
                      ),
                    ),
                  ],
                  if (below != null) ...[
                    SizedBox(height: tokens.spacing.md),
                    below,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: tokens.spacing.sm),
              Padding(
                padding: EdgeInsets.only(top: tokens.spacing.xs),
                child: trailing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A connector that needs the user: its own card, the reason in plain words
/// (the connector's own sentence), and the one button that fixes it.
class _AttentionCard extends ConsumerStatefulWidget {
  const _AttentionCard({required this.entry});
  final ConnectorEntry entry;

  @override
  ConsumerState<_AttentionCard> createState() => _AttentionCardState();
}

class _AttentionCardState extends ConsumerState<_AttentionCard> {
  bool _working = false;

  Future<void> _fix() async {
    final id = widget.entry.connector.id;
    final actions = ref.read(connectorActionsProvider);
    setState(() => _working = true);
    try {
      // A revoked OS grant cannot be re-asked in-app once the system says
      // "don't ask again": the settings page is the fix.
      if (widget.entry.status.state == ConnectorState.permissionDenied) {
        await actions.openSystemSettings(id);
      } else {
        await actions.connect(id);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final c = widget.entry.connector;
    final status = widget.entry.status;
    final copy = copyFor(c.id);
    final denied = status.state == ConnectorState.permissionDenied;
    final reason =
        status.detail ??
        (denied
            ? '${copy.name} access is off. Open settings to turn it on.'
            : 'Something needs your attention.');
    return DecoratedBox(
      key: ValueKey('connector-${c.id}'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
        border: Border.all(color: tokens.warning, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SettingsIconTile(copy.icon, color: tokens.warning),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(copy.name, style: theme.textTheme.titleMedium),
                      SizedBox(height: tokens.spacing.xs),
                      StatusText(statusLine(status, when: (_) => '')),
                    ],
                  ),
                ),
                SizedBox(width: tokens.spacing.sm),
                FilledButton(
                  key: ValueKey('connector-${c.id}-action'),
                  onPressed: _working ? null : _fix,
                  child: Text(denied ? 'Open settings' : copy.fixLabel),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            Text(reason, style: theme.textTheme.bodyMedium),
            SizedBox(height: tokens.spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: PressableScale(
                onTap: () => showConnectorSheet(context, connectorId: c.id),
                semanticLabel: 'More about ${copy.name}',
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
                  child: Text(
                    'Details and disconnect',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
    );
    return Semantics(
      label: 'Loading connectors',
      child: SettingsGroup(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              key: ValueKey('connectors-skeleton-$i'),
              padding: EdgeInsets.all(tokens.spacing.base),
              child: Row(
                children: [
                  bar(40, 40),
                  SizedBox(width: tokens.spacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(120, 14),
                      SizedBox(height: tokens.spacing.sm),
                      bar(200, 12),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NothingAvailable extends ConsumerWidget {
  const _NothingAvailable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connectors could not start',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Nothing was changed. Try again; if it keeps happening, restart '
              '${AppIdentity.shortName}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.base),
            FilledButton.tonal(
              key: const ValueKey('connectors-retry'),
              onPressed: () => ref.invalidate(connectorHubProvider),
              child: const Text('Try again'),
            ),
            SizedBox(height: tokens.spacing.sm),
            TextButton(
              onPressed: () => context.go('/ask'),
              child: const Text('Go to Ask'),
            ),
          ],
        ),
      ),
    );
  }
}
