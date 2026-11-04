/// The sheet behind a connector row: what it reads, its state, the fix when
/// one is needed, folder index controls, notification apps to skip, and
/// Disconnect (confirmed, in plain words, with the option to also open the OS
/// permission page, because an app cannot revoke an OS grant itself).
library;

import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/format/when.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/dhruva_sheet.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/folder_index_status.dart';
import '../state/connector_copy.dart';
import 'settings_widgets.dart';

Future<void> showConnectorSheet(
  BuildContext context, {
  required String connectorId,
}) => showDhruvaSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ConnectorSheet(connectorId: connectorId),
);

/// What the user picked in the Disconnect confirmation.
enum DisconnectChoice { cancel, disconnect, disconnectAndOpenSettings }

Future<DisconnectChoice> confirmDisconnect(
  BuildContext context,
  ConnectorCopy copy,
) async {
  // Platform chrome (Rule 6): a Cupertino alert on iOS (actions stack, so the
  // long label no longer wraps awkwardly), the Material dialog on Android.
  final cupertino = Theme.of(context).platform == TargetPlatform.iOS;
  Widget action(
    Key? key,
    String label,
    DisconnectChoice value, {
    bool primary = false,
  }) {
    void pick() => Navigator.pop(context, value);
    if (cupertino) {
      return CupertinoDialogAction(
        key: key,
        isDefaultAction: primary,
        isDestructiveAction: primary,
        onPressed: pick,
        child: Text(label),
      );
    }
    return primary
        ? FilledButton(key: key, onPressed: pick, child: Text(label))
        : TextButton(key: key, onPressed: pick, child: Text(label));
  }

  final choice = await showAdaptiveDialog<DisconnectChoice>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('Disconnect ${copy.name}?'),
      content: Text(copy.disconnectEffect),
      actions: [
        action(null, 'Cancel', DisconnectChoice.cancel),
        if (copy.hasOsPermission)
          action(
            const ValueKey('disconnect-and-settings'),
            'Disconnect and open Settings',
            DisconnectChoice.disconnectAndOpenSettings,
          ),
        action(
          const ValueKey('disconnect-confirm'),
          'Disconnect',
          DisconnectChoice.disconnect,
          primary: true,
        ),
      ],
    ),
  );
  return choice ?? DisconnectChoice.cancel;
}

class ConnectorSheet extends ConsumerStatefulWidget {
  const ConnectorSheet({super.key, required this.connectorId});
  final String connectorId;

  @override
  ConsumerState<ConnectorSheet> createState() => _ConnectorSheetState();
}

class _ConnectorSheetState extends ConsumerState<ConnectorSheet> {
  bool _working = false;

  String get _id => widget.connectorId;

  Future<void> _disconnect(ConnectorCopy copy) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final choice = await confirmDisconnect(context, copy);
    if (choice == DisconnectChoice.cancel || !mounted) return;
    setState(() => _working = true);
    try {
      final unfinished = await ref
          .read(connectorActionsProvider)
          .disconnect(
            _id,
            openSystemSettings:
                choice == DisconnectChoice.disconnectAndOpenSettings,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            unfinished ??
                '${copy.name} disconnected. The copy on this phone is deleted.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't disconnect ${copy.name}. Try again, or turn it off "
            'in system settings.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _fix(ConnectorStatus status) async {
    final actions = ref.read(connectorActionsProvider);
    setState(() => _working = true);
    try {
      if (status.state == ConnectorState.permissionDenied) {
        await actions.openSystemSettings(_id);
      } else {
        await actions.connect(_id);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final copy = copyFor(_id);
    final entry = ref
        .watch(connectorListProvider)
        .value
        ?.where((e) => e.connector.id == _id)
        .firstOrNull;
    // Disconnected while the sheet was open: nothing left to show.
    final status = entry?.status ?? ConnectorStatus.notConnected;
    final line = statusLine(
      status,
      when: (d) => shortWhen(d, DateTime.now(), (t) => clockText(context, t)),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        0,
        tokens.spacing.base,
        tokens.spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SettingsIconTile(copy.icon),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(copy.name, style: theme.textTheme.titleLarge),
                    SizedBox(height: tokens.spacing.xs),
                    _Status(line),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.base),
          Text(
            'What it can read',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(copy.reads, style: theme.textTheme.bodyMedium),
          if (needsFix(status)) ...[
            SizedBox(height: tokens.spacing.base),
            _FixBox(
              reason: status.detail ?? 'Something needs your attention.',
              label: status.state == ConnectorState.permissionDenied
                  ? 'Open settings'
                  : copy.fixLabel,
              busy: _working,
              onPressed: () => _fix(status),
            ),
          ],
          if (_id == ConnectorIds.folder && status.isConnected ||
              _id == ConnectorIds.folder && needsFix(status))
            FolderSection(status: status),
          if (_id == ConnectorIds.notifications) const _NotificationsSection(),
          SizedBox(height: tokens.spacing.base),
          if (copy.hasOsPermission &&
              status.state != ConnectorState.notConnected)
            ListTile(
              key: const ValueKey('connector-open-settings'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Open system settings'),
              subtitle: const Text(
                'Where you switch this permission off or on again.',
              ),
              onTap: () =>
                  ref.read(connectorActionsProvider).openSystemSettings(_id),
            ),
          if (status.state != ConnectorState.notConnected)
            ListTile(
              key: const ValueKey('connector-disconnect'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Disconnect',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(copy.disconnectEffect),
              enabled: !_working,
              onTap: () => _disconnect(copy),
            ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.line);
  final StatusLine line;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final theme = Theme.of(context);
    final color = switch (line.tone) {
      StatusTone.ok => tokens.success,
      StatusTone.attention => tokens.warning,
      StatusTone.off => theme.colorScheme.onSurfaceVariant,
    };
    return Row(
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

class _FixBox extends StatelessWidget {
  const _FixBox({
    required this.reason,
    required this.label,
    required this.busy,
    required this.onPressed,
  });
  final String reason;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radius.lg),
        border: Border.all(color: tokens.warning, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: theme.textTheme.bodyMedium),
            SizedBox(height: tokens.spacing.md),
            FilledButton(
              key: const ValueKey('connector-sheet-fix'),
              onPressed: busy ? null : onPressed,
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- folder -------------------------------------------------------------------

/// Index status, "Index now" (explicit, with progress, cancellable) and
/// "Change folder".
class FolderSection extends ConsumerStatefulWidget {
  const FolderSection({super.key, required this.status});
  final ConnectorStatus status;

  @override
  ConsumerState<FolderSection> createState() => _FolderSectionState();
}

class _FolderSectionState extends ConsumerState<FolderSection> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final files = ref.watch(folderFilesProvider).value ?? const [];
    final account = ref
        .watch(connectorAccountsProvider)
        .value
        ?.where((a) => a.connector == ConnectorIds.folder)
        .firstOrNull;
    final indexing = widget.status.state == ConnectorState.syncing;
    final index = FolderIndexStatus.of(
      files,
      total: account?.config['total'] as int?,
    );
    final actions = ref.read(connectorActionsProvider);

    Future<void> run() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final r = await actions.indexFolder();
        if (r.skipped != null) {
          messenger.showSnackBar(SnackBar(content: Text(r.skipped!)));
        }
      } on ConnectorException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Index',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (account?.label != null) ...[
            SizedBox(height: tokens.spacing.xs),
            Text(account!.label!, style: theme.textTheme.bodyMedium),
          ],
          SizedBox(height: tokens.spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radius.full),
            child: LinearProgressIndicator(
              key: const ValueKey('folder-progress'),
              value: indexing && index.fraction == null
                  ? null
                  : index.fraction ?? 0,
              minHeight: 6,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            '${index.headline()} · ${index.detail(indexing: indexing)}',
            key: const ValueKey('folder-index-status'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          Wrap(
            spacing: tokens.spacing.sm,
            runSpacing: tokens.spacing.sm,
            children: [
              if (indexing)
                OutlinedButton(
                  key: const ValueKey('folder-cancel-index'),
                  onPressed: actions.cancelIndex,
                  child: const Text('Cancel'),
                )
              else
                FilledButton.tonal(
                  key: const ValueKey('folder-index-now'),
                  onPressed: run,
                  child: const Text('Index now'),
                ),
              OutlinedButton(
                key: const ValueKey('folder-change'),
                onPressed: indexing ? null : actions.chooseFolder,
                child: const Text('Change folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- notifications --------------------------------------------------------------

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How access works',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'Android keeps notifications behind a special switch. Turning it on '
            'opens the system page; find this app and allow it. You can switch '
            'it off there at any time.',
            style: theme.textTheme.bodyMedium,
          ),
          ListTile(
            key: const ValueKey('notification-apps'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Apps to skip'),
            subtitle: const Text(
              'Notifications from these apps are never saved.',
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => showDhruvaSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => const ExcludedAppsSheet(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The apps that have posted notifications, each with a switch to skip it.
class ExcludedAppsSheet extends ConsumerWidget {
  const ExcludedAppsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final groups = ref.watch(notificationGroupsProvider).value ?? const [];
    final account = ref
        .watch(connectorAccountsProvider)
        .value
        ?.where((a) => a.connector == ConnectorIds.notifications)
        .firstOrNull;
    final excluded = {
      for (final e in (account?.config['excluded'] as List?) ?? const [])
        if (e is String) e,
    };
    // Apps already skipped but with nothing saved still need a switch to undo.
    final seen = {for (final g in groups) g.package: g.appLabel};
    for (final p in excluded) {
      seen.putIfAbsent(p, () => p);
    }
    seen.remove('');
    final apps = seen.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    Future<void> toggle(String pkg, bool skip) {
      final next = {...excluded};
      skip ? next.add(pkg) : next.remove(pkg);
      return ref.read(connectorActionsProvider).setExcludedApps(next.toList());
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: tokens.spacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
              child: Text('Apps to skip', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacing.base,
                tokens.spacing.xs,
                tokens.spacing.base,
                tokens.spacing.sm,
              ),
              child: Text(
                'Switch an app on to stop saving its notifications. What is '
                'already saved from it stays for up to 7 days.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (apps.isEmpty)
              Padding(
                padding: EdgeInsets.all(tokens.spacing.base),
                child: Text(
                  'No apps yet. An app shows up here after it posts its first '
                  'notification.',
                  key: const ValueKey('excluded-apps-empty'),
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in apps)
                      SwitchListTile(
                        key: ValueKey('skip-${a.key}'),
                        title: Text(a.value),
                        subtitle: Text(a.key == a.value ? '' : a.key),
                        value: excluded.contains(a.key),
                        onChanged: (v) => toggle(a.key, v),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
