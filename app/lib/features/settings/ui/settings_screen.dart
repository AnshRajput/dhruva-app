/// Settings screen (Amendment 4b, lands the credit-row shortcut from
/// Amendment 2b): Storage summary + link to the Models hub's Installed tab,
/// Data (clear all chat history behind a double confirmation), About (a
/// slim tile to the dedicated `/settings/about` keepsake page + the credit
/// row shortcut — the About page is the canonical home for the rest).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../app_info.dart';
import '../state/storage_summary_provider.dart';
import '../widgets/credit_row.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        children: const [
          _SectionHeader('Storage'),
          _StorageTile(),
          _SectionHeader('Data'),
          _ClearHistoryTile(),
          _SectionHeader('About'),
          _AboutTile(),
          CreditRow(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.md,
        tokens.spacing.xs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _StorageTile extends ConsumerWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(storageSummaryProvider);
    return ListTile(
      leading: const Icon(Icons.sd_storage_outlined),
      title: const Text('Installed models'),
      subtitle: switch (summary) {
        AsyncData(:final value) => Text(
          '${value.modelCount} model'
          '${value.modelCount == 1 ? '' : 's'} · '
          '${_formatBytes(value.totalBytes)} used',
        ),
        AsyncError() => const Text("Couldn't read storage usage"),
        _ => const Text('Loading…'),
      },
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/models'),
    );
  }
}

class _ClearHistoryTile extends ConsumerWidget {
  const _ClearHistoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_sweep_outlined, color: scheme.error),
      title: Text(
        'Clear all chat history',
        style: TextStyle(color: scheme.error),
      ),
      subtitle: const Text('Deletes every conversation and message'),
      onTap: () => _clearAllHistory(context, ref),
    );
  }

  Future<void> _clearAllHistory(BuildContext context, WidgetRef ref) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all chat history?'),
        content: const Text(
          'This permanently deletes every conversation and message on '
          'this device. Downloaded models are NOT affected — they stay '
          'installed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !context.mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          "This can't be undone — all conversations and messages will be "
          'gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all history'),
          ),
        ],
      ),
    );
    if (secondConfirm != true || !context.mounted) return;

    await ref.read(chatRepositoryProvider).clearAllHistory();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Chat history cleared. Pull to refresh the Chat tab to see it.',
        ),
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About Dhruva AI'),
      subtitle: const Text('Version $appVersion'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/settings/about'),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '$bytes B';
}
