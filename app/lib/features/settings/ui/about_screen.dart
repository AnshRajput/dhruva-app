/// About page (`/settings/about`). Order (audit D9): version and build first,
/// then the privacy facts and links, then the developer credit, and the
/// pole-star story and pull quotes last.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/identity/app_identity.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../app_info.dart';
import '../privacy_facts.dart';
import '../widgets/credit_row.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/update_row.dart';
import '../widgets/version_text.dart';

/// Drawn from the ratified brand narrative (orchestra/research/
/// brand-proposal.md §a/§d) — the pole-star myth, the privacy conviction
/// (§d's onboarding hero line, verbatim), and device ownership/
/// self-reliance. Not marketing copy: each line traces to something
/// already said elsewhere in the app or its design docs.
const _quotes = [
  'Dhruva sat still until the sky organized itself around him, and became '
      'the one fixed point every navigator can still find — without a '
      'signal, a satellite, or anyone’s permission.',
  'Your AI. Your phone. Nobody else’s business.',
  'Every model you run here lives on your device. No rented intelligence, '
      'no cloud bill, no one else’s server standing between you and a '
      'machine you actually own.',
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SettingsPage(
      title: 'About',
      subtitle: AppIdentity.tagline,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
          child: Row(
            children: [
              DhruvaStar(size: 28, color: theme.colorScheme.primary),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppIdentity.productName,
                      style: theme.textTheme.titleMedium,
                    ),
                    VersionText(style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spacing.base),
        const SettingsGroup(children: [UpdateRow()]),
        const SettingsSectionLabel('Privacy in short'),
        SettingsGroup(
          children: [
            const SettingsRow(
              icon: Icons.lock_outline,
              title: 'Zero telemetry',
              subtitle:
                  'Nothing about you or your chats is sent to us. '
                  '$noServerFact',
            ),
            SettingsRow(
              key: const ValueKey('about-privacy-row'),
              icon: Icons.info_outline,
              title: 'See every network call',
              subtitle:
                  'Model downloads, AI news, update checks, your accounts',
              onTap: () => context.push('/settings/privacy'),
            ),
          ],
        ),
        const SettingsSectionLabel('Links'),
        const SettingsGroup(
          children: [
            _LinkRow(
              icon: Icons.description_outlined,
              label: 'Privacy policy',
              url: privacyPolicyUrl,
            ),
            _LinkRow(
              icon: Icons.code,
              label: 'Source on GitHub',
              url: githubUrl,
            ),
            _LinkRow(icon: Icons.language, label: 'Website', url: websiteUrl),
            _LinkRow(
              icon: Icons.gavel_outlined,
              label: 'Apache License 2.0',
              url: licenseUrl,
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.lg),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('The developer', style: theme.textTheme.titleSmall),
              SizedBox(height: tokens.spacing.xs),
              Text(
                'Built by Ansh Singh Rajput under Appu Inside Engineering, '
                'building in public — every loop of this app ships on GitHub '
                'as it happens.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const CreditRow(),
        SizedBox(height: tokens.spacing.xl),
        // The story comes last: the pole star, its name in its own script,
        // and the three pull quotes.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: DhruvaStar(size: 96, color: theme.colorScheme.primary),
              ),
              SizedBox(height: tokens.spacing.md),
              // The name's own meaning, in its own script (design-tokens.json
              // meta.story). `titleLarge` is a Fraunces role, so this is the
              // bundled Noto Serif Devanagari fallback's live consumer.
              Center(
                child: Text(
                  'ध्रुव',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(height: tokens.spacing.xl2),
              for (final quote in _quotes) _PullQuote(quote),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pull quote: Fraunces (`headlineSmall`, italic, the "myth register" per
/// brand-proposal.md section c), set plainly with no side stripe or card.
class _PullQuote extends StatelessWidget {
  final String text;
  const _PullQuote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.lg),
      child: Text(
        text,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkRow({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SettingsIconTile(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
