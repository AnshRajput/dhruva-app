/// Settings > Privacy (`/settings/privacy`): the exact network facts in plain
/// words, what is stored on the phone, why backups are off, the two privacy
/// switches (app switcher, home widget), clear-history, and the policy link.
/// Text lives in `privacy_facts.dart` so About and this screen never disagree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/settings/bool_pref.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../app_info.dart';
import '../privacy_facts.dart';
import '../widgets/clear_history_row.dart';
import '../widgets/settings_widgets.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final hide = ref.watch(hideInAppSwitcherProvider).value;
    final widgetTitle = ref.watch(widgetShowNextEventProvider).value;
    final androidWidget = theme.platform == TargetPlatform.android;

    return SettingsPage(
      title: 'Privacy',
      subtitle: 'Exactly what leaves this phone, and what stays.',
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
          child: DecoratedBox(
            key: const ValueKey('privacy-no-server'),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(tokens.radius.full),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.base,
                vertical: tokens.spacing.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  SizedBox(width: tokens.spacing.md),
                  Expanded(
                    child: Text(
                      noServerFact,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SettingsSectionLabel('The only network calls'),
        SettingsGroup(
          children: [
            for (final f in networkFacts)
              SettingsRow(icon: f.icon, title: f.title, subtitle: f.body),
          ],
        ),
        const SettingsNote(reportsFact),
        const SettingsSectionLabel('On this phone'),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.smartphone,
              title: 'What is stored',
              subtitle: storedOnPhoneFor(Theme.of(context).platform),
            ),
            const SettingsRow(
              icon: Icons.lock_outline_rounded,
              // The body opens "Backups are off." itself.
              title: 'Cloud backup',
              subtitle: backupsOffFact,
            ),
          ],
        ),
        SettingsSectionLabel(androidWidget ? 'Screen and widget' : 'Screen'),
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              key: const ValueKey('hide-in-switcher-switch'),
              icon: Icons.visibility_outlined,
              title: 'Hide content in app switcher',
              subtitle:
                  'Shows a blank card instead of your screen when you switch '
                  'apps. On Android this also blocks screenshots.',
              value: hide,
              onChanged: (v) =>
                  ref.read(hideInAppSwitcherProvider.notifier).set(v),
            ),
            // The home widget exists on Android only (iOS has no widget
            // extension), so the switch would do nothing there.
            if (androidWidget)
              SettingsSwitchRow(
                key: const ValueKey('widget-next-event-switch'),
                icon: Icons.widgets_outlined,
                title: 'Show next event title on the home widget',
                subtitle:
                    'Your own calendar only. The widget never shows mail or '
                    'notifications.',
                value: widgetTitle,
                onChanged: (v) =>
                    ref.read(widgetShowNextEventProvider.notifier).set(v),
              ),
          ],
        ),
        const SettingsSectionLabel('Your data'),
        const SettingsGroup(children: [ClearHistoryRow()]),
        const SettingsSectionLabel('Policy'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('privacy-policy-row'),
              icon: Icons.description_outlined,
              title: 'Privacy policy',
              subtitle: 'The full text, on GitHub',
              trailing: const Icon(Icons.open_in_new, size: 16),
              onTap: () => launchUrl(
                Uri.parse(privacyPolicyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
