/// Settings > Notifications (`/settings/notifications`).
///
/// Live today: the download-alert switch (honoured by the downloader, see
/// `downloadNotificationConfig`).
///
/// Morning brief: the preference (`morningBriefEnabledProvider`,
/// `morningBriefMinutesProvider`) is stored, but there is NO scheduler yet, and
/// the app has no local-notification dependency. A switch that does nothing
/// would be a lie, so the screen shows an honest "Arrives with Today's brief"
/// row instead.
// TODO(wave-3, Today brief): replace [_MorningBriefComingRow] with a switch
// bound to morningBriefEnabledProvider plus a time picker bound to
// morningBriefMinutesProvider, once the scheduler exists (a delivery path such
// as flutter_local_notifications + exact-alarm policy has to be chosen and
// reviewed for network use first).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/bool_pref.dart';
import '../widgets/settings_widgets.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(downloadNotificationsProvider).value;
    return SettingsPage(
      title: 'Notifications',
      subtitle: 'Only what you ask for. Nothing is sent from a server.',
      children: [
        SettingsGroup(
          children: [
            const _MorningBriefComingRow(),
            SettingsSwitchRow(
              key: const ValueKey('download-alerts-switch'),
              icon: Icons.download_outlined,
              title: 'Download alerts',
              subtitle:
                  'Tell me when a model finishes or fails. A progress '
                  'notification still shows while it downloads, so Android '
                  'keeps it running.',
              value: alerts,
              onChanged: (v) =>
                  ref.read(downloadNotificationsProvider.notifier).set(v),
            ),
          ],
        ),
      ],
    );
  }
}

class _MorningBriefComingRow extends StatelessWidget {
  const _MorningBriefComingRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsRow(
      key: const ValueKey('morning-brief-coming'),
      icon: Icons.wb_sunny_outlined,
      title: 'Morning brief',
      subtitle: "Arrives with Today's brief. Off until then.",
      trailing: Text(
        'Soon',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
