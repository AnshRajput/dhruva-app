/// The privacy ledger on the Connectors screen and its full-list screen: the
/// one fact ("0 bytes sent to any [AppIdentity.shortName] server. There isn't
/// one."), then what
/// was read and when, newest first. The ledger holds counts only, never
/// content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/format/when.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../state/connector_copy.dart';
import 'settings_widgets.dart';

/// Entries shown on the Connectors screen before "See all".
const ledgerPreviewCount = 5;

/// The headline fact, as the comp words it.
String get ledgerFact =>
    '0 bytes sent to any ${AppIdentity.shortName} server. There isn\'t one.';

class LedgerFactBanner extends StatelessWidget {
  const LedgerFactBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Semantics(
      container: true,
      child: DecoratedBox(
        key: const ValueKey('ledger-fact'),
        decoration: BoxDecoration(
          color: tokens.success.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.base,
            vertical: tokens.spacing.md,
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: tokens.success),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Text(ledgerFact, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  const LedgerRow({super.key, required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final copy = copyFor(entry.connector);
    final when = shortWhen(
      entry.at,
      DateTime.now(),
      (d) => clockText(context, d),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.base,
        vertical: tokens.spacing.sm,
      ),
      child: Row(
        children: [
          SettingsIconTile(copy.icon),
          SizedBox(width: tokens.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ledgerTitle(entry), style: theme.textTheme.bodyLarge),
                Text(
                  ledgerSource(entry),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.spacing.sm),
          Text(
            when,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Privacy ledger" header + fact + the latest entries + "See all".
class LedgerSection extends ConsumerWidget {
  const LedgerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final entries = ref.watch(ledgerProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.spacing.base,
            tokens.spacing.base,
            tokens.spacing.sm,
            tokens.spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Privacy ledger',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('ledger-see-all'),
                onPressed: () => context.push('/settings/connectors/ledger'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
          child: const LedgerFactBanner(),
        ),
        SizedBox(height: tokens.spacing.sm),
        if (entries == null)
          const SizedBox.shrink()
        else if (entries.isEmpty)
          const SettingsNote(
            'Nothing has been read yet. When a connector reads from your '
            'phone, each read is listed here with the time.',
          )
        else
          for (final e in entries.take(ledgerPreviewCount)) LedgerRow(entry: e),
      ],
    );
  }
}
