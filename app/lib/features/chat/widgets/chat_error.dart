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

  /// Last-resort action, shown after the secondary one (e.g. "Re-download
  /// (379 MB)").
  final ChatRecoveryAction? tertiaryAction;
  final String? tertiaryLabel;

  const ChatErrorContent({
    required this.message,
    required this.primaryAction,
    required this.primaryLabel,
    this.secondaryAction,
    this.secondaryLabel,
    this.tertiaryAction,
    this.tertiaryLabel,
  });
}

/// "379 MB" / "1.2 GB" for a re-download label.
String _sizeLabel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).round()} MB';
}

/// [modelSizeBytes] (the installed file's real size) fills in the
/// "Re-download (379 MB)" label; omitted, the label has no size.
ChatErrorContent chatErrorContentFor(String? errorKind, {int? modelSizeBytes}) {
  switch (errorKind) {
    // D2: three distinct load failures, one recovery order: Try again, then
    // Use a smaller model, then (only when the file is the suspect) the
    // expensive Re-download with its real size.
    case 'EngineOutOfMemoryFailure':
      return const ChatErrorContent(
        message:
            'Not enough free memory for this model right now. Close other '
            'apps and try again, or use a smaller model.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Try again',
        secondaryAction: ChatRecoveryAction.smallerModel,
        secondaryLabel: 'Use a smaller model',
      );
    case 'EngineLoadTimeoutFailure':
      return const ChatErrorContent(
        message:
            'The model took too long to start. Your phone may be busy or '
            'low on memory, so the file is probably fine.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Try again',
        secondaryAction: ChatRecoveryAction.smallerModel,
        secondaryLabel: 'Use a smaller model',
      );
    case 'EngineLoadFailure':
      return ChatErrorContent(
        message:
            "This model's file couldn't be read. It may be damaged, missing "
            'or an unsupported format.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Try again',
        secondaryAction: ChatRecoveryAction.smallerModel,
        secondaryLabel: 'Use a smaller model',
        tertiaryAction: ChatRecoveryAction.redownload,
        tertiaryLabel: modelSizeBytes == null
            ? 'Re-download'
            : 'Re-download (${_sizeLabel(modelSizeBytes)})',
      );
    case 'EngineDisposedFailure':
      return const ChatErrorContent(
        message: 'The model was unloaded.',
        primaryAction: ChatRecoveryAction.reloadModel,
        primaryLabel: 'Reload model',
      );
    case 'EngineStateFailure':
      return const ChatErrorContent(
        message:
            'The model is busy with something else, like a speed test. Try '
            'again in a moment.',
        primaryAction: ChatRecoveryAction.retry,
        primaryLabel: 'Retry',
      );
    case 'EngineDecodeFailure':
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
              if (content.tertiaryAction != null)
                TextButton(
                  onPressed: () => onAction(content.tertiaryAction!),
                  child: Text(content.tertiaryLabel!),
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
