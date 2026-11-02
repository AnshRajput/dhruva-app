/// Shared building blocks for the Settings surfaces, in the visual language of
/// the approved Connectors comp: a large serif title with one plain line under
/// it, grouped rounded surfaces with hairline dividers, a soft icon tile per
/// row, one-line descriptions. All colors, text styles, spacing and radii come
/// from the theme tokens. Nothing here animates (settings are visited rarely;
/// the platform ripple on press is the only feedback).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart';

/// A settings page: chrome app bar (Rule 6, via [ChromeScaffold]), big title,
/// optional one-line subtitle, then [children].
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return ChromeScaffold(
      appBar: const AdaptiveAppBar(),
      bodyBuilder: (context, inset) => ListView(
        padding: EdgeInsets.only(
          top: inset.top + tokens.spacing.xs,
          bottom: inset.bottom + tokens.spacing.xl2,
        ),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineLarge),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: tokens.spacing.base),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Small label above a [SettingsGroup].
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.lg,
        tokens.spacing.base,
        tokens.spacing.base,
        tokens.spacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Rounded surface holding rows, with hairline dividers between them.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        divided.add(
          Divider(
            height: 1,
            thickness: 0.5,
            indent: tokens.spacing.base + 40 + tokens.spacing.md,
            color: theme.colorScheme.outlineVariant,
          ),
        );
      }
      divided.add(children[i]);
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
        child: Column(children: divided),
      ),
    );
  }
}

/// The soft rounded tile the row icon sits in.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Icon(icon, size: 22, color: color ?? theme.colorScheme.primary),
    );
  }
}

/// A navigation row: icon tile, title, one-line description, chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleWidget,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Replaces the [subtitle] text (e.g. the live version line).
  final Widget? subtitleWidget;
  final VoidCallback? onTap;

  /// Replaces the chevron (e.g. a status label).
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: SettingsIconTile(icon, color: destructive ? scheme.error : null),
      title: Text(
        title,
        style: destructive ? TextStyle(color: scheme.error) : null,
      ),
      subtitle: subtitleWidget ?? Text(subtitle),
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right, size: 20)),
      onTap: onTap,
    );
  }
}

/// A switch row with the same anatomy as [SettingsRow]. While the saved value
/// is still loading (`value == null`) the switch is disabled, never wrong.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // `.adaptive`: a Cupertino switch on iOS (Rule 6), Material on Android.
    return SwitchListTile.adaptive(
      secondary: SettingsIconTile(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value ?? false,
      onChanged: value == null ? null : onChanged,
    );
  }
}

/// A plain-words paragraph under a group (the "one trust line" per screen).
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.lg,
        tokens.spacing.sm,
        tokens.spacing.lg,
        0,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
