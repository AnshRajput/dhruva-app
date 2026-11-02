/// The full privacy ledger (`/settings/connectors/ledger`): every recorded
/// read, newest first, with a way to clear the list. Clearing forgets the
/// history (counts only); it never touches data or connectors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../widgets/ledger_widgets.dart';
import '../widgets/settings_widgets.dart';

class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the ledger?'),
        content: const Text(
          'This empties the list below. It does not delete any data and does '
          'not disconnect anything. The ledger only ever holds counts and '
          'times, never what was read.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('ledger-clear-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear ledger'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(connectorStoreProvider).clearLedger();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final entries = ref.watch(ledgerProvider).value;
    return SettingsPage(
      title: 'Privacy ledger',
      subtitle: 'Everything your connectors have read, newest first.',
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
          child: const LedgerFactBanner(),
        ),
        SizedBox(height: tokens.spacing.sm),
        if (entries == null)
          const SizedBox.shrink()
        else if (entries.isEmpty)
          const SettingsNote(
            'The ledger is empty. When a connector reads from your phone, '
            'each read is listed here.',
          )
        else ...[
          for (final e in entries) LedgerRow(entry: e),
          SizedBox(height: tokens.spacing.base),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('ledger-clear'),
                onPressed: () => _clear(context, ref),
                child: const Text('Clear ledger'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
