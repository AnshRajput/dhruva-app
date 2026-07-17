/// Amendment 2b, EXACT copy: "Made with ❤️ by Ansh Singh Rajput", tapping
/// opens https://anshgandharva.online. The About page (Amendment 4, the
/// UX-amendment follow-up) is its canonical home; Settings keeps this same
/// slim row as a shortcut rather than duplicating the copy.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../app_info.dart';

class CreditRow extends StatelessWidget {
  const CreditRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Semantics(
      button: true,
      label: 'Made with love by Ansh Singh Rajput. Opens his portfolio site.',
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(creatorUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Made with ', style: theme.textTheme.bodyMedium),
              Icon(Icons.favorite, size: 14, color: theme.colorScheme.error),
              Text(' by Ansh Singh Rajput', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
