/// Settings screen (opened from the gear on Today; Amendment 4b, lands the credit-row shortcut from
/// Amendment 2b): Storage summary + link to the Models hub's Installed tab,
/// Data (clear all chat history behind a double confirmation), About (a
/// slim tile to the dedicated `/settings/about` keepsake page + the credit
/// row shortcut — the About page is the canonical home for the rest).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_health/device_health_provider.dart';
import '../../../core/di/providers.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/appearance_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/update/shorebird_update_banner.dart' show updIosReady;
import '../../../core/update/shorebird_update_service.dart';
import '../../../core/widgets/platform_chrome.dart' show isCupertinoChrome;
import '../state/storage_summary_provider.dart';
import '../widgets/credit_row.dart';
import '../widgets/version_text.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        children: const [
          _SectionHeader('Appearance'),
          _AppearanceTile(),
          _ReduceTransparencyTile(),
          _SectionHeader('Models'),
          _NavTile(
            tileKey: 'settings-models',
            icon: Icons.widgets_outlined,
            title: 'Models & downloads',
            subtitle: 'Discover, installed, voice, speed test',
            route: '/settings/models',
          ),
          _NavTile(
            tileKey: 'settings-compare',
            icon: Icons.science_outlined,
            title: 'Compare models',
            subtitle: 'Run one prompt through two models',
            route: '/settings/models/compare',
          ),
          _NavTile(
            tileKey: 'settings-ai-news',
            icon: Icons.newspaper_outlined,
            title: 'AI news',
            subtitle: 'Small models worth trying (opt-in)',
            route: '/settings/models/compare?tab=news',
          ),
          _NavTile(
            tileKey: 'settings-voice',
            icon: Icons.record_voice_over_outlined,
            title: 'Voice',
            subtitle: 'Speech models for talking hands-free',
            route: '/settings/models?tab=voice',
          ),
          _SectionHeader('Connectors'),
          _NavTile(
            tileKey: 'settings-connectors',
            icon: Icons.link_outlined,
            title: 'Connectors',
            subtitle: 'Calendar, contacts, folder, notifications',
            route: '/settings/connectors',
          ),
          _SectionHeader('Storage'),
          _StorageTile(),
          _SectionHeader('Data'),
          _ClearHistoryTile(),
          _SectionHeader('Device'),
          _DeviceGuardTile(),
          _SectionHeader('Safety'),
          _SafetyTile(),
          _CrashReportsTile(),
          _SectionHeader('About'),
          _UpdateTile(),
          _AboutTile(),
          CreditRow(),
        ],
      ),
    );
  }
}

/// Plain navigation row to a full-screen route.
class _NavTile extends StatelessWidget {
  final String tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _NavTile({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(tileKey),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}

/// Appearance: System / Light / Dark, persisted (`themeModeProvider`).
class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.md,
        vertical: tokens.spacing.xs,
      ),
      child: SegmentedButton<ThemeMode>(
        key: const ValueKey('appearance-segments'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('System')),
          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
        ],
        selected: {mode},
        onSelectionChanged: (s) =>
            ref.read(themeModeProvider.notifier).set(s.single),
      ),
    );
  }
}

/// iOS only: solid bars instead of the translucent glass approximation.
class _ReduceTransparencyTile extends ConsumerWidget {
  const _ReduceTransparencyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isCupertinoChrome(context)) return const SizedBox.shrink();
    final on = ref.watch(reduceTransparencyProvider).value ?? false;
    return SwitchListTile(
      key: const ValueKey('reduce-transparency-switch'),
      secondary: const Icon(Icons.blur_off_outlined),
      title: const Text('Reduce transparency'),
      subtitle: const Text('Use solid tab and app bars instead of blur.'),
      value: on,
      onChanged: (v) => ref.read(reduceTransparencyProvider.notifier).set(v),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.xs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _StorageTile extends ConsumerWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider);
    return ListTile(
      leading: const Icon(Icons.sd_storage_outlined),
      title: const Text('Installed models'),
      subtitle: switch (summary) {
        AsyncData(:final value) => Text(
          '${value.modelCount} model'
          '${value.modelCount == 1 ? '' : 's'} · '
          '${_formatBytes(value.totalBytes)} used',
        ),
        AsyncError() => const Text("Couldn't read storage usage"),
        _ => const Text('Loading…'),
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/models'),
    );
  }
}

class _DeviceGuardTile extends ConsumerWidget {
  const _DeviceGuardTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(deviceGuardEnabledProvider).value ?? true;
    return SwitchListTile(
      key: const ValueKey('device-guard-switch'),
      secondary: const Icon(Icons.warning_amber),
      title: const Text('Battery & heat guard'),
      subtitle: const Text(
        'Warns you, and stops a reply, when your phone is low on battery '
        'or too hot.',
      ),
      value: enabled,
      onChanged: (v) => ref.read(deviceGuardEnabledProvider.notifier).set(v),
    );
  }
}

class _ClearHistoryTile extends ConsumerWidget {
  const _ClearHistoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_sweep_outlined, color: scheme.error),
      title: Text(
        'Clear all chat history',
        style: TextStyle(color: scheme.error),
      ),
      subtitle: const Text('Deletes every conversation and message'),
      onTap: () => _clearAllHistory(context, ref),
    );
  }

  Future<void> _clearAllHistory(BuildContext context, WidgetRef ref) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all chat history?'),
        content: const Text(
          'This permanently deletes every conversation and message on '
          'this device. Downloaded models are NOT affected — they stay '
          'installed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          "This can't be undone — all conversations and messages will be "
          'gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all history'),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !context.mounted) return;

    await ref.read(chatRepositoryProvider).clearAllHistory();
    // UX-hardening A2: refresh the kept-alive Chat list immediately (no more
    // "pull to refresh" instruction) via the shared revision signal — settings
    // can't import `features/chat`'s controller (ADR-002).
    ref.read(conversationListRevisionProvider.notifier).bump();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Chat history cleared.')));
  }
}

class _SafetyTile extends StatelessWidget {
  const _SafetyTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.flag_outlined),
      title: const Text('Safety & reports'),
      subtitle: const Text('Report a reply, see your reports'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/safety'),
    );
  }
}

class _CrashReportsTile extends StatelessWidget {
  const _CrashReportsTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('Crash reports'),
      subtitle: const Text('Stay on your phone unless you share them'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/crash-reports'),
    );
  }
}

/// "Check for updates": tap forces a check, or downloads / restarts per phase.
class _UpdateTile extends ConsumerWidget {
  const _UpdateTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shorebirdUpdateProvider);
    final n = ref.read(shorebirdUpdateProvider.notifier);
    void say(String m) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    final (String sub, VoidCallback? tap) = switch (s.phase) {
      ShorebirdPhase.unavailable => (
        "Updates aren't available in this build",
        null,
      ),
      ShorebirdPhase.available => ('Update available', n.download),
      ShorebirdPhase.downloading => ('Downloading update\u2026', null),
      ShorebirdPhase.readyToRestart =>
        s.reopenByHand
            ? (updIosReady, null)
            : ('Update ready. Tap to restart', n.restart),
      ShorebirdPhase.failed => ('Update failed. Tap to retry', n.download),
      ShorebirdPhase.idle => (
        s.patch == null ? 'Up to date' : 'Patch ${s.patch}',
        () async {
          final ok = await n.check(force: true);
          if (!context.mounted) return;
          if (!ok) {
            say("Couldn't check for updates.");
          } else if (ref.read(shorebirdUpdateProvider).phase ==
              ShorebirdPhase.idle) {
            say("You're up to date.");
          }
        },
      ),
    };
    return ListTile(
      key: const ValueKey('update-row'),
      leading: const Icon(Icons.system_update_alt_rounded),
      title: const Text('Check for updates'),
      subtitle: Text(sub),
      enabled: tap != null || s.phase == ShorebirdPhase.downloading,
      onTap: tap,
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About ${AppIdentity.productName}'),
      subtitle: const VersionText(),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/about'),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '$bytes B';
}
