/// Onboarding step 3: "Start with your day" (comp onboarding-connect.png).
///
/// One primary action, Connect your calendar (the phone's own calendar, no
/// sign-in), and an always-there "Not now". Folder and, on Android,
/// Notifications are optional extras. If the OS says no, the step says what
/// to do (Open settings) instead of failing quietly. A slim strip at the top
/// keeps the background model download visible, with its recovery.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../state/onboarding_controller.dart';

class ConnectStep extends ConsumerStatefulWidget {
  const ConnectStep({
    super.key,
    required this.onDone,
    required this.onRetryDownload,
  });

  /// Marks onboarding complete and goes to Today (also what Skip does).
  final Future<void> Function() onDone;

  /// Restarts the model download after a failure.
  final VoidCallback onRetryDownload;

  @override
  ConsumerState<ConnectStep> createState() => _ConnectStepState();
}

class _ConnectStepState extends ConsumerState<ConnectStep> {
  bool _busy = false;
  String? _error;

  /// Where the last tap on Allow ended when the system permission was not
  /// granted (same as the Connectors row): the connector's own sentence, and
  /// whether only system settings is left. Null after a grant. A blocked
  /// Calendar that later connects (the app root finishes it on resume, after
  /// the user allowed it in settings) moves on by itself.
  ConnectorStatus? _denied;
  bool _finished = false;

  ConnectorStatus? _status(String id) {
    final list = ref.watch(connectorListProvider).value ?? const [];
    for (final e in list) {
      if (e.connector.id == id) return e.status;
    }
    return null;
  }

  Future<void> _allow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final status = await connectAndSync(ref, ConnectorIds.calendar);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (status == null) {
        _error = "Couldn't reach your calendar. Try again in a moment.";
      }
      _denied = status != null && status.detail != null && !status.isConnected
          ? status
          : null;
    });
  }

  Future<void> _add(String id) async {
    await connectAndSync(ref, id);
  }

  Future<void> _openSettings(String id) async {
    try {
      final hub = await ref.read(connectorHubProvider.future);
      await hub.byId(id)?.openSystemSettings();
    } on Object {
      // The row keeps saying what to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final calendar = _status(ConnectorIds.calendar);
    final connected = calendar?.isConnected ?? false;
    // The connector words every case. First Deny on Android: its retry
    // sentence, Allow stays. Second Deny (or access switched off later): Open
    // settings.
    final denied = calendar?.state == ConnectorState.notConnected
        ? _denied
        : null;
    final blocked =
        (denied?.needsSettings ?? false) ||
        calendar?.state == ConnectorState.permissionDenied;
    final retryText = blocked || connected ? null : denied?.detail;
    if (connected && (_denied?.needsSettings ?? false) && !_finished) {
      _finished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.onDone());
      });
    }
    final notifications = _status(ConnectorIds.notifications);

    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: _StepBars(active: 2)),
              TextButton(
                key: const ValueKey('connect-skip'),
                onPressed: () => widget.onDone(),
                child: const Text('Skip'),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          _DownloadStrip(onRetry: widget.onRetryDownload),
          SizedBox(height: tokens.spacing.lg),
          Text('Start with your day', style: theme.textTheme.headlineLarge),
          SizedBox(height: tokens.spacing.md),
          Text(
            '${AppIdentity.shortName} reads the calendar already on this '
            'phone. No sign-in needed.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          const _ExampleDay(),
          SizedBox(height: tokens.spacing.sm),
          Center(
            child: Text(
              'Example. Yours will appear on Today.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          if (connected) ...[
            Row(
              key: const ValueKey('connect-calendar-done'),
              children: [
                Icon(Icons.check_circle, color: tokens.success, size: 20),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    'Calendar connected. Your day is waiting on Today.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            FilledButton(
              key: const ValueKey('connect-continue'),
              onPressed: () => widget.onDone(),
              child: const Text('Continue to Today'),
            ),
          ] else if (blocked) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 20),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    denied?.detail ??
                        calendar?.detail ??
                        'Calendar access is off. Open settings and allow '
                            'Calendar.',
                    key: const ValueKey('connect-calendar-denied'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            FilledButton(
              key: const ValueKey('connect-open-settings'),
              onPressed: () => _openSettings(ConnectorIds.calendar),
              child: const Text('Open settings'),
            ),
            TextButton(
              key: const ValueKey('connect-not-now'),
              onPressed: () => widget.onDone(),
              child: const Text('Not now'),
            ),
          ] else ...[
            if (retryText != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: scheme.error, size: 20),
                  SizedBox(width: tokens.spacing.sm),
                  Expanded(
                    child: Text(
                      retryText,
                      key: const ValueKey('connect-calendar-denied'),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacing.md),
            ],
            FilledButton(
              key: const ValueKey('connect-allow'),
              onPressed: _busy ? null : _allow,
              child: Text(_busy ? 'Connecting…' : 'Connect your calendar'),
            ),
            TextButton(
              key: const ValueKey('connect-not-now'),
              onPressed: () => widget.onDone(),
              child: const Text('Not now'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.spacing.sm),
              child: Text(
                _error!,
                key: const ValueKey('connect-error'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          SizedBox(height: tokens.spacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 14, color: tokens.success),
              SizedBox(width: tokens.spacing.xs),
              Flexible(
                child: Text(
                  'Stays on this phone. Nothing is uploaded.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.xl),
          Text('Add more, if you like', style: theme.textTheme.titleLarge),
          SizedBox(height: tokens.spacing.sm),
          _ExtraRow(
            rowKey: 'folder',
            icon: Icons.folder_outlined,
            title: 'Notes folder',
            subtitle: 'Ask questions about your files',
            status: _status(ConnectorIds.folder),
            onAdd: () => _add(ConnectorIds.folder),
            onSettings: () => _openSettings(ConnectorIds.folder),
          ),
          // Android only: the connector is absent on iOS.
          if (notifications != null &&
              notifications.state != ConnectorState.unsupported)
            _ExtraRow(
              rowKey: 'notifications',
              icon: Icons.notifications_none,
              title: 'Notification summary',
              subtitle: 'One calm digest, Android only',
              status: notifications,
              onAdd: () => _add(ConnectorIds.notifications),
              onSettings: () => _openSettings(ConnectorIds.notifications),
            ),
        ],
      ),
    );
  }
}

/// Four thin bars, [active] of them lit (welcome, model, calendar, Today).
class _StepBars extends StatelessWidget {
  const _StepBars({required this.active});
  final int active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Semantics(
      label: 'Step ${active + 1} of 4',
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radius.full),
                color: i <= active
                    ? scheme.primary.withValues(alpha: i == active ? 1 : 0.5)
                    : scheme.outlineVariant,
              ),
            ),
            SizedBox(width: tokens.spacing.xs),
          ],
        ],
      ),
    );
  }
}

/// The model download, carried along: progress while it runs, "ready" when it
/// lands, and the same recovery as the download step when it fails.
class _DownloadStrip extends ConsumerWidget {
  const _DownloadStrip({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(onboardingDownloadControllerProvider).value;
    final status = dl?.status ?? OnboardingDownloadStatus.idle;
    if (status == OnboardingDownloadStatus.idle) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final failed = status == OnboardingDownloadStatus.failed;
    final done = status == OnboardingDownloadStatus.installed;
    final pct = ((dl?.progress ?? 0) * 100).round();
    final label = failed
        ? "Download didn't finish. ${dl?.errorMessage ?? ''}".trim()
        : done
        ? 'Your model is ready.'
        : pct > 0
        ? 'Your model is downloading in the background · $pct%'
        : 'Getting your model ready in the background…';
    return DecoratedBox(
      key: const ValueKey('connect-download-strip'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : done
                      ? Icons.check_circle
                      : Icons.downloading_rounded,
                  size: 18,
                  color: failed
                      ? scheme.error
                      : done
                      ? tokens.success
                      : scheme.primary,
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
                if (failed)
                  TextButton(
                    key: const ValueKey('connect-download-retry'),
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
              ],
            ),
            if (!failed && !done)
              Padding(
                padding: EdgeInsets.only(top: tokens.spacing.xs),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.radius.full),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: (dl?.progress ?? 0) > 0 ? dl!.progress : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A made-up day, clearly labelled as an example, so the step shows what
/// Today will look like before anything is allowed.
class _ExampleDay extends StatelessWidget {
  const _ExampleDay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    const rows = [
      ('9:30', 'Design sync', 'Ravi, Sana, Dev'),
      ('11:00', 'Budget review', 'Room 4B'),
      ('1:30', 'Lunch with Ananya', 'Social, Indiranagar'),
    ];
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(tokens.radius.xl),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.base),
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) Divider(height: tokens.spacing.lg),
                Opacity(
                  opacity: i == rows.length - 1 ? 0.5 : 1,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(r.$1, style: theme.textTheme.titleSmall),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$2, style: theme.textTheme.titleMedium),
                            Text(
                              r.$3,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onAdd,
    required this.onSettings,
  });

  final String rowKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final ConnectorStatus? status;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final s = status?.state;
    final added = s == ConnectorState.connected || s == ConnectorState.syncing;
    final fix =
        s == ConnectorState.needsAttention ||
        s == ConnectorState.permissionDenied;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(tokens.radius.lg),
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.md),
              child: Icon(icon, color: scheme.onPrimaryContainer),
            ),
          ),
          SizedBox(width: tokens.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(
                  fix ? (status?.detail ?? subtitle) : subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          if (added)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 18, color: tokens.success),
                SizedBox(width: tokens.spacing.xs),
                Text('Added', style: theme.textTheme.labelLarge),
              ],
            )
          else
            OutlinedButton(
              key: ValueKey('connect-extra-$rowKey'),
              onPressed: fix ? onSettings : onAdd,
              child: Text(fix ? 'Open settings' : 'Add'),
            ),
        ],
      ),
    );
  }
}
