/// About page (UX-amendment follow-up to Amendment 4): a keepsake screen,
/// not a settings row — app identity, the brand narrative as pull quotes,
/// the developer credit, and the canonical links row. Reached from
/// Settings via `/settings/about`.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../app_info.dart';
import '../widgets/credit_row.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: DhruvaStar(size: 96, color: theme.colorScheme.primary),
            ),
            SizedBox(height: tokens.spacing.md),
            Center(
              child: Text(
                'Dhruva AI',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: tokens.spacing.xs),
            Center(
              child: Text(
                'Version $appVersion (build $appBuildNumber)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.xl2),
            for (final quote in _quotes) _PullQuote(quote),
            SizedBox(height: tokens.spacing.md),
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
            const CreditRow(),
            SizedBox(height: tokens.spacing.md),
            const Divider(),
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
            SizedBox(height: tokens.spacing.sm),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.md),
              child: Text(
                'Zero telemetry — downloads are the only network calls this '
                'app makes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pull quote: Fraunces (`headlineSmall`, italic — the "myth register",
/// per brand-proposal.md §c) with the same left-border blockquote language
/// chat-spec.md §2.2 already uses for markdown block quotes, at keepsake
/// scale instead of in-bubble scale.
class _PullQuote extends StatelessWidget {
  final String text;
  const _PullQuote(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.lg),
      child: Container(
        padding: EdgeInsets.only(left: tokens.spacing.sm),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outline,
              width: tokens.spacing.xs,
            ),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontStyle: FontStyle.italic,
          ),
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
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
