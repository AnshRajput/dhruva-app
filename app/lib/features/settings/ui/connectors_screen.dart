/// Connectors placeholder (`/settings/connectors`). Every "connect" call to
/// action in Wave 1 (Today's brief, Up next, inbox card; Library's folder
/// row; the timeline) lands here. The real screen (state per connector,
/// privacy ledger, revoke) is Wave 2B; this one states plainly what is coming
/// and offers things that work today, so it is never a dead end.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/identity/app_identity.dart';
import '../../../core/theme/dhruva_theme_extension.dart';

class ConnectorsScreen extends StatelessWidget {
  const ConnectorsScreen({super.key});

  static const _connectors = <(IconData, String, String)>[
    (Icons.calendar_today_outlined, 'Calendar', 'Your meetings, no sign-in.'),
    (Icons.people_outline, 'Contacts', 'Who you are meeting.'),
    (Icons.folder_outlined, 'Notes folder', 'Search your files on this phone.'),
    (Icons.notifications_none, 'Notifications', 'A calm digest (Android).'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Connectors')),
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.base),
        children: [
          Text(
            'Choose what ${AppIdentity.shortName} can read. Everything stays '
            'on this phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.base),
          for (final (icon, name, blurb) in _connectors)
            ListTile(
              leading: Icon(icon),
              title: Text(name),
              subtitle: Text(blurb),
              trailing: Text(
                'Not available yet',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(height: tokens.spacing.base),
          Text(
            'Connecting arrives in an upcoming update. Meanwhile:',
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: tokens.spacing.sm),
          Wrap(
            spacing: tokens.spacing.sm,
            children: [
              FilledButton.tonal(
                key: const ValueKey('connectors-open-ask'),
                onPressed: () => context.go('/ask'),
                child: const Text('Ask something'),
              ),
              FilledButton.tonal(
                key: const ValueKey('connectors-open-actions'),
                onPressed: () => context.push('/actions'),
                child: const Text('Open Actions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
