/// Report-a-reply bottom sheet (Google Play AI-Generated Content policy:
/// users can flag offensive output without leaving the app). Saves locally
/// via `ReportRepository`; emailing the developer is a second, explicit
/// button. Nothing leaves the phone otherwise.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/providers.dart';
import '../../../core/safety/report_mail.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/safety/report_repository.dart';
import '../../settings/app_info.dart';

Future<void> showReportSheet(
  BuildContext context, {
  required MessageInfo message,
  String? modelName,
  required VoidCallback onReported,
}) {
  final tokens = Theme.of(context).extension<DhruvaTokens>()!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: tokens.motion.moderate,
      reverseDuration: tokens.motion.fast,
    ),
    builder: (_) => ReportSheet(
      message: message,
      modelName: modelName,
      onReported: onReported,
    ),
  );
}

class ReportSheet extends ConsumerStatefulWidget {
  final MessageInfo message;
  final String? modelName;
  final VoidCallback onReported;

  const ReportSheet({
    super.key,
    required this.message,
    this.modelName,
    required this.onReported,
  });

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool email}) async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() => _busy = true);
    final m = widget.message;
    final note = _note.text.trim();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(reportRepositoryProvider)
        .submit(
          conversationId: m.conversationId,
          messageId: m.id,
          reason: reason,
          content: m.content,
          modelName: widget.modelName,
          note: note,
        );
    widget.onReported();
    navigator.pop();
    var message = 'Reported. Thanks, it stays on your phone.';
    if (email) {
      final launched = await _launchMail(
        reportMailto(
          reason: reason.label,
          note: note,
          model: widget.modelName,
          appVersion: appVersion,
          excerpt: m.content.length > ReportRepository.maxExcerptLength
              ? m.content.substring(0, ReportRepository.maxExcerptLength)
              : m.content,
        ),
      );
      if (!launched) message = 'Reported, but no email app was found.';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _launchMail(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          tokens.spacing.sm,
          tokens.spacing.lg,
          tokens.spacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report this reply', style: theme.textTheme.titleMedium),
              SizedBox(height: tokens.spacing.xs),
              Text(
                'Reports stay on your phone unless you choose to email them.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tokens.spacing.md),
              Wrap(
                spacing: tokens.spacing.sm,
                runSpacing: tokens.spacing.xs,
                children: [
                  for (final r in ReportReason.values)
                    ChoiceChip(
                      label: Text(r.label),
                      selected: _reason == r,
                      onSelected: (_) => setState(() => _reason = r),
                    ),
                ],
              ),
              SizedBox(height: tokens.spacing.md),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Add a note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: tokens.spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reason == null || _busy
                          ? null
                          : () => unawaited(_submit(email: false)),
                      child: const Text('Report'),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _reason == null || _busy
                          ? null
                          : () => unawaited(_submit(email: true)),
                      child: const Text(
                        'Report & email developer',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
