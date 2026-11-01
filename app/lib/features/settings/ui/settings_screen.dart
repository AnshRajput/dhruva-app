/// Settings home (opened from the gear on Today). Grouped in the visual
/// language of the Connectors comp: big title, grouped rounded surfaces, an
/// icon tile + title + one plain line per row. Order: Connectors, About me,
/// Models, Appearance, Notifications, Privacy, Safety & reports, Crash
/// reports, About. Everything that used to sit inline here now lives one tap
/// away with its topic: theme -> Appearance, clear history -> Privacy,
/// update check -> About.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_health/device_health_provider.dart';
import '../../../core/identity/app_identity.dart';
import '../state/storage_summary_provider.dart';
import '../widgets/credit_row.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/version_text.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Settings',
      subtitle:
          'Choose what ${AppIdentity.shortName} can read, and how it '
          'behaves.',
      children: [
        SettingsGroup(
          children: [
            _nav(
              context,
              'settings-connectors',
              Icons.link_outlined,
              'Connectors',
              'Calendar, contacts, folder, notifications',
              '/settings/connectors',
            ),
            _nav(
              context,
              'settings-about-me',
              Icons.edit_note_rounded,
              'About me',
              'Your name, work and writing style, so drafts sound like you',
              '/settings/about-me',
            ),
          ],
        ),
        const SettingsSectionLabel('Models'),
        SettingsGroup(
          children: [
            const _ModelsRow(),
            _nav(
              context,
              'settings-compare',
              Icons.science_outlined,
              'Compare models',
              'Run one prompt through two models',
              '/settings/models/compare',
            ),
            _nav(
              context,
              'settings-ai-news',
              Icons.newspaper_outlined,
              'AI news',
              'Small models worth trying (opt-in)',
              '/settings/models/compare?tab=news',
            ),
            _nav(
              context,
              'settings-voice',
              Icons.record_voice_over_outlined,
              'Voice',
              'Speech models for talking hands-free',
              '/settings/models?tab=voice',
            ),
            const _DeviceGuardRow(),
          ],
        ),
        const SettingsSectionLabel('This app'),
        SettingsGroup(
          children: [
            _nav(
              context,
              'settings-appearance',
              Icons.wb_sunny_outlined,
              'Appearance',
              'Light, dark, or follow your phone',
              '/settings/appearance',
            ),
            _nav(
              context,
              'settings-notifications',
              Icons.notifications_none,
              'Notifications',
              'Download alerts and your morning brief',
              '/settings/notifications',
            ),
            _nav(
              context,
              'settings-privacy',
              Icons.lock_outline,
              'Privacy',
              'What leaves this phone, what stays, and your data',
              '/settings/privacy',
            ),
          ],
        ),
        const SettingsSectionLabel('Trust'),
        SettingsGroup(
          children: [
            _nav(
              context,
              'settings-safety',
              Icons.flag_outlined,
              'Safety & reports',
              'Report a reply, see your reports',
              '/settings/safety',
            ),
            _nav(
              context,
              'settings-crash-reports',
              Icons.error_outline,
              'Crash reports',
              'Stay on your phone unless you share them',
              '/settings/crash-reports',
            ),
            const _AboutRow(),
          ],
        ),
        const CreditRow(),
      ],
    );
  }

  static Widget _nav(
    BuildContext context,
    String key,
    IconData icon,
    String title,
    String subtitle,
    String route,
  ) => SettingsRow(
    key: ValueKey(key),
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () => context.push(route),
  );
}

/// "Models & downloads": the one-line description doubles as the storage
/// summary once it has loaded (the old standalone "Installed models" row).
class _ModelsRow extends ConsumerWidget {
  const _ModelsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider);
    return SettingsRow(
      key: const ValueKey('settings-models'),
      icon: Icons.widgets_outlined,
      title: 'Models & downloads',
      subtitle: switch (summary) {
        AsyncData(:final value) when value.modelCount > 0 =>
          '${value.modelCount} model${value.modelCount == 1 ? '' : 's'} · '
              '${_formatBytes(value.totalBytes)} used',
        AsyncError() => "Couldn't read storage usage",
        _ => 'Discover, installed, speed test',
      },
      onTap: () => context.push('/settings/models'),
    );
  }
}

class _DeviceGuardRow extends ConsumerWidget {
  const _DeviceGuardRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(deviceGuardEnabledProvider).value;
    return SettingsSwitchRow(
      key: const ValueKey('device-guard-switch'),
      icon: Icons.warning_amber,
      title: 'Battery & heat guard',
      subtitle:
          'Warns you, and stops a reply, when your phone is low on battery '
          'or too hot.',
      value: enabled ?? true,
      onChanged: (v) => ref.read(deviceGuardEnabledProvider.notifier).set(v),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey('settings-about'),
      icon: Icons.info_outline,
      title: 'About ${AppIdentity.productName}',
      subtitle: '',
      subtitleWidget: const VersionText(),
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
