/// No model is installed yet but one is downloading (Today's Prep and Plan my
/// day open Ask before it finishes): say so with the progress, and keep the
/// question that was typed for the user. The thread sends it when the model
/// lands.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/model_download_line.dart';
import '../../../data/downloads/download_manager.dart';

class ModelDownloadingView extends StatelessWidget {
  const ModelDownloadingView({
    super.key,
    required this.progress,
    required this.pendingPrompt,
    required this.onOpenDownloads,
  });

  final DownloadProgress progress;
  final String? pendingPrompt;
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final prompt = pendingPrompt?.trim();
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModelDownloadLine(progress: progress),
                SizedBox(height: tokens.spacing.base),
                if (prompt != null && prompt.isNotEmpty) ...[
                  Text(
                    'Your question is saved and is sent when the model is '
                    'ready:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  Text(
                    prompt,
                    key: const ValueKey('model-downloading-prompt'),
                    style: theme.textTheme.titleMedium,
                  ),
                ] else
                  Text(
                    'You can chat as soon as it is ready.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                SizedBox(height: tokens.spacing.lg),
                OutlinedButton(
                  onPressed: onOpenDownloads,
                  child: const Text('See downloads'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
