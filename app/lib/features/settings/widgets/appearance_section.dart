/// Appearance, folded into Settings (it used to be a page holding one
/// control): System / Light / Dark as a segmented control right in the "This
/// app" group, plus, on iOS, the "Reduce transparency" override for the
/// glass-chrome approximation. Both persist through `appearance_providers.dart`.
///
/// The control is platform chrome (Rule 6): Material `SegmentedButton` (pill)
/// on Android, `CupertinoSlidingSegmentedControl` on iOS.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart' show isCupertinoChrome;
import 'settings_widgets.dart';

class AppearanceRow extends ConsumerWidget {
  const AppearanceRow({super.key});

  static const _labels = {
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    void set(ThemeMode m) => ref.read(themeModeProvider.notifier).set(m);

    final control = isCupertinoChrome(context)
        ? CupertinoSlidingSegmentedControl<ThemeMode>(
            key: const ValueKey('appearance-segments'),
            groupValue: mode,
            thumbColor: theme.colorScheme.primaryContainer,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            children: {
              for (final e in _labels.entries)
                e.key: Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
                  child: Text(
                    e.value,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            },
            onValueChanged: (m) {
              if (m != null) set(m);
            },
          )
        : SegmentedButton<ThemeMode>(
            key: const ValueKey('appearance-segments'),
            showSelectedIcon: false,
            segments: [
              for (final e in _labels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => set(s.single),
          );

    return Padding(
      padding: EdgeInsets.all(tokens.spacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SettingsIconTile(Icons.wb_sunny_outlined),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Appearance', style: theme.textTheme.bodyLarge),
                    Text(
                      'Light, dark, or follow your phone',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.md),
          SizedBox(width: double.infinity, child: control),
        ],
      ),
    );
  }
}

/// iOS only: solid bars instead of the blur approximation.
class ReduceTransparencyRow extends ConsumerWidget {
  const ReduceTransparencyRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSwitchRow(
      key: const ValueKey('reduce-transparency-switch'),
      icon: Icons.blur_off_outlined,
      title: 'Reduce transparency',
      subtitle: 'Use solid tab and app bars instead of blur.',
      value: ref.watch(reduceTransparencyProvider).value,
      onChanged: (v) => ref.read(reduceTransparencyProvider.notifier).set(v),
    );
  }
}
