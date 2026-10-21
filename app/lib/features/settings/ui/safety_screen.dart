/// Safety & reports (Google Play AI-Generated Content policy; Apple 1.2):
/// how replies are generated, the user's saved reports (local only, with
/// delete), and a way to contact the developer. Reached from Settings via
/// `/settings/safety`.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/providers.dart';
import '../../../core/safety/report_mail.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/safety/report_repository.dart';

class SafetyScreen extends ConsumerWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final reports = ref.watch(contentReportsProvider);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Safety & reports')),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        children: [
          Padding(
            padding: EdgeInsets.all(tokens.spacing.md),
            child: Text(
              'Dhruva generates every reply on your phone with the model you '
              'chose. Models can be wrong, and can sometimes produce '
              'offensive or unsafe text. Use the flag on any reply to report '
              'it.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          _Header('Your reports'),
          switch (reports) {
            AsyncData(:final value) when value.isEmpty => Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.md,
                vertical: tokens.spacing.sm,
              ),
              child: Text('No reports yet.', style: muted),
            ),
            AsyncData(:final value) => Column(
              children: [for (final r in value) _ReportTile(report: r)],
            ),
            AsyncError() => Padding(
              padding: EdgeInsets.all(tokens.spacing.md),
              child: Text("Couldn't read your reports.", style: muted),
            ),
            _ => const SizedBox.shrink(),
          },
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.md,
              tokens.spacing.sm,
              tokens.spacing.md,
              tokens.spacing.sm,
            ),
            child: Text(
              "We use reports to improve Dhruva's default safety rules.",
              style: muted,
            ),
          ),
          _Header('Contact'),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Contact developer'),
            subtitle: const Text(developerEmail),
            onTap: () => unawaited(
              launchUrl(
                developerMailto(subject: 'Dhruva AI'),
                mode: LaunchMode.externalApplication,
              ).catchError((_) => false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  const _Header(this.label);

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

class _ReportTile extends ConsumerWidget {
  final ContentReportInfo report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = report.createdAt;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text('${report.reason.label} · $date'),
      subtitle: Text(
        report.excerpt,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Delete report',
        icon: const Icon(Icons.delete_outline),
        onPressed: () =>
            unawaited(ref.read(reportRepositoryProvider).delete(report.id)),
      ),
    );
  }
}
