import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crash/crash_actions.dart';
import '../../../core/crash/crash_log.dart';
import '../../../core/theme/dhruva_theme_extension.dart';

/// Settings -> Crash reports. Local only; sharing is always the user's call.
class CrashReportsScreen extends ConsumerWidget {
  const CrashReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final reports = ref.watch(crashReportsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crash reports'),
        actions: [
          if (reports.isNotEmpty) ...[
            IconButton(
              key: const ValueKey('crash-share-all'),
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share),
              onPressed: () => shareCrashReport(reports),
            ),
            IconButton(
              key: const ValueKey('crash-email-all'),
              tooltip: 'Email developer',
              icon: const Icon(Icons.mail_outline),
              onPressed: () => emailCrashReport(reports),
            ),
            IconButton(
              key: const ValueKey('crash-delete-all'),
              tooltip: 'Delete all',
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: () => _deleteAll(context, ref),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        children: [
          Padding(
            padding: EdgeInsets.all(tokens.spacing.md),
            child: Text(
              'Crash reports stay on your phone. Nothing is sent unless you '
              'choose to share it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (reports.isEmpty) const ListTile(title: Text('No crash reports.')),
          for (final r in reports)
            ListTile(
              title: Text(r.errorType),
              subtitle: Text(
                '${r.timestamp.toLocal().toString().substring(0, 16)} · '
                '${r.firstLine}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _view(context, r),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all crash reports?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('crash-delete-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(crashLogProvider).clear();
    ref.invalidate(crashReportsProvider);
    ref.invalidate(unseenCrashReportsProvider);
  }

  void _view(BuildContext context, CrashRecord r) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(r.errorType),
            actions: [
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: () => shareCrashReport([r]),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              r.toText(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    );
  }
}
