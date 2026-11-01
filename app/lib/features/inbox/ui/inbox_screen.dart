/// Inbox: mail and notifications in one calm list. Wave 1 ships the empty
/// "connect" state only; the tab itself is hidden until an inbox source
/// exists (`inboxAvailableProvider`). Also reachable full-screen at
/// `/inbox/connect` from Today's "Set up your inbox" card, in which case the
/// app bar shows a back button.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, this.standalone = false});

  /// True when shown as a full-screen route (not the shell tab).
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return ChromeScaffold(
      appBar: AdaptiveAppBar(
        title: const Text('Inbox'),
        automaticallyImplyLeading: standalone,
      ),
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.base),
        children: [
          NextStepCard(
            icon: Icons.inbox_outlined,
            title: 'Your inbox, in one calm list',
            body:
                'Connect mail or, on Android, the notification digest. Each '
                'row gets a one-line summary and a drafted reply you edit and '
                'send yourself. Nothing leaves this phone.',
            actionLabel: 'Connect an inbox source',
            actionKey: const ValueKey('inbox-connect'),
            onAction: () => context.push('/settings/connectors'),
          ),
        ],
      ),
    );
  }
}
