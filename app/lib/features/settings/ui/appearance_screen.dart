/// Settings > Appearance (`/settings/appearance`): System / Light / Dark and,
/// on iOS, the "Reduce transparency" override for the glass-chrome
/// approximation. Both persist through `appearance_providers.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart' show isCupertinoChrome;
import '../widgets/settings_widgets.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final reduce = ref.watch(reduceTransparencyProvider).value;
    return SettingsPage(
      title: 'Appearance',
      subtitle:
          'Light, dark, or follow your phone. Text size follows your '
          "phone's setting.",
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
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
        ),
        if (isCupertinoChrome(context)) ...[
          SizedBox(height: tokens.spacing.base),
          SettingsGroup(
            children: [
              SettingsSwitchRow(
                key: const ValueKey('reduce-transparency-switch'),
                icon: Icons.blur_off_outlined,
                title: 'Reduce transparency',
                subtitle: 'Use solid tab and app bars instead of blur.',
                value: reduce,
                onChanged: (v) =>
                    ref.read(reduceTransparencyProvider.notifier).set(v),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
