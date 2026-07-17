/// Error taxonomy → message + recovery affordance (chat-spec.md §8),
/// keyed off `MessageInfo.errorKind` — the free-text `EngineFailure.
/// runtimeType` label `ChatRepository.finalize` persists (see
/// `ChatController._onError`). `EngineStateFailure`/`EngineValidationFailure`
/// fall through to the generic decode-failure copy per the spec table's own
/// notes ("shouldn't reach the UI... if it does, treat as
/// EngineDecodeFailure's generic case").
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

enum ChatRecoveryAction {
  retry,
  retryAnyway,
  smallerModel,
  redownload,
  reloadModel,
  copyDetails,
}

final class ChatErrorContent {
  final String message;
  final ChatRecoveryAction primaryAction;
  final String primaryLabel;
  final ChatRecoveryAction? secondaryAction;
  final String? secondaryLabel;

  const ChatErrorContent({
    required this.message,
    required this.primaryAction,
    required this.primaryLabel,
    this.secondaryAction,
    this.secondaryLabel,
  });
}

ChatErrorContent chatErrorContentFor(String? errorKind) {
  switch (errorKind) {
    case 'EngineOutOfMemoryFailure':
      return const ChatErrorContent(
        message:
            'This model needs more memory than your device has free right now.',
        primaryAction: ChatRecoveryAction.smallerModel,
        primaryLabel: 'Try a smaller model',
        secondaryAction: ChatRecoveryAction.retryAnyway,
        secondaryLabel: 'Retry anyway',
      );
    case 'EngineLoadFailure':
      return const ChatErrorContent(
        message:
            "Couldn't load this model — the file may be corrupted or an unsupported format.",
        primaryAction: ChatRecoveryAction.redownload,
        primaryLabel: 'Re-download',
      );
    case 'EngineDisposedFailure':
      return const ChatErrorContent(
        message: 'The model was unloaded.',
        primaryAction: ChatRecoveryAction.reloadModel,
        primaryLabel: 'Reload model',
      );
    case 'EngineDecodeFailure':
    case 'EngineStateFailure':
    case 'EngineValidationFailure':
      return const ChatErrorContent(
        message: 'Something went wrong generating a response.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Retry',
      );
    default:
      return const ChatErrorContent(
        message: 'Something unexpected happened.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Retry',
        secondaryAction: ChatRecoveryAction.copyDetails,
        secondaryLabel: 'Copy error details',
      );
  }
}

/// Compact inline card at the position the failed assistant message would
/// have occupied — never a full-screen error, never a snackbar.
class ChatErrorCard extends StatelessWidget {
  final ChatErrorContent content;
  final void Function(ChatRecoveryAction action) onAction;

  const ChatErrorCard({
    super.key,
    required this.content,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final onContainer = theme.colorScheme.onErrorContainer;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: onContainer, size: 20),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  content.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onContainer,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.sm),
          Wrap(
            spacing: tokens.spacing.sm,
            children: [
              FilledButton(
                onPressed: () => onAction(content.primaryAction),
                child: Text(content.primaryLabel),
              ),
              if (content.secondaryAction != null)
                TextButton(
                  onPressed: () => onAction(content.secondaryAction!),
                  child: Text(content.secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> copyErrorDetails(BuildContext context, String details) async {
  await Clipboard.setData(
    ClipboardData(
      text: details.isEmpty ? 'No further details available.' : details,
    ),
  );
}
