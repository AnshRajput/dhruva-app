/// Settings > Notifications (`/settings/notifications`).
///
/// * Morning brief: a daily local notification at the chosen time. Off by
///   default; turning it on asks for the notification permission, and if the
///   phone says no the switch stays off and the screen says how to fix it. The
///   notification text is generic ("Your brief is ready to read") and never
///   carries anything from your calendar or messages.
/// * Download alerts: honoured by the downloader (`downloadNotificationConfig`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/intents/app_settings.dart';
import '../../../core/notifications/morning_brief.dart';
import '../../../core/settings/bool_pref.dart';
import '../widgets/settings_widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// The OS refused the permission when the user turned the brief on.
  bool _blocked = false;

  Future<void> _setBrief(bool on) async {
    final enabled = ref.read(morningBriefEnabledProvider.notifier);
    final scheduler = ref.read(morningBriefSchedulerProvider);
    if (!on) {
      setState(() => _blocked = false);
      await enabled.set(false);
      await scheduler.disable();
      return;
    }
    final minutes = await ref.read(morningBriefMinutesProvider.future);
    bool granted;
    try {
      granted = await scheduler.enable(minutes);
    } on Object {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _blocked = !granted);
    if (granted) await enabled.set(true);
  }

  Future<void> _pickTime() async {
    final current =
        ref.read(morningBriefMinutesProvider).value ??
        MorningBriefTimeNotifier.defaultMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await ref.read(morningBriefMinutesProvider.notifier).set(minutes);
    if (ref.read(morningBriefEnabledProvider).value ?? false) {
      try {
        await ref.read(morningBriefSchedulerProvider).schedule(minutes);
      } on Object {
        // The next app launch re-schedules.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(downloadNotificationsProvider).value;
    final briefOn = ref.watch(morningBriefEnabledProvider).value ?? false;
    final minutes =
        ref.watch(morningBriefMinutesProvider).value ??
        MorningBriefTimeNotifier.defaultMinutes;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return SettingsPage(
      title: 'Notifications',
      subtitle: 'Only what you ask for. Nothing is sent from a server.',
      children: [
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              key: const ValueKey('morning-brief-switch'),
              icon: Icons.wb_sunny_outlined,
              title: 'Morning brief',
              subtitle:
                  'A daily nudge to read your brief. It only says “$morningBriefBody”, '
                  'never anything from your calendar or messages.',
              value: briefOn,
              onChanged: _setBrief,
            ),
            if (briefOn)
              SettingsRow(
                key: const ValueKey('morning-brief-time'),
                icon: Icons.calendar_today_outlined,
                title: 'Time',
                subtitle: 'Arrives around this time, within a few minutes.',
                trailing: Text(time),
                onTap: _pickTime,
              ),
            if (_blocked)
              SettingsRow(
                key: const ValueKey('morning-brief-blocked'),
                icon: Icons.error_outline,
                title: 'Notifications are off for this app',
                subtitle:
                    'Allow notifications in your phone settings, then turn the '
                    'morning brief on again.',
                trailing: TextButton(
                  key: const ValueKey('morning-brief-open-settings'),
                  onPressed: () => ref.read(openAppSettingsProvider)(),
                  child: const Text('Open settings'),
                ),
              ),
            SettingsSwitchRow(
              key: const ValueKey('download-alerts-switch'),
              icon: Icons.download_outlined,
              title: 'Download alerts',
              // The progress-notification sentence is Android only: it is
              // the foreground-service notification that keeps a download
              // alive there. iOS has no such thing.
              subtitle: Theme.of(context).platform == TargetPlatform.iOS
                  ? 'Tell me when a model finishes or fails.'
                  : 'Tell me when a model finishes or fails. A progress '
                        'notification still shows while it downloads, so your '
                        'phone keeps it running.',
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
