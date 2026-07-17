/// `MessageInfo` (`data/chat/chat_repository.dart`) has no `copyWith` — it's
/// a plain immutable data holder, and `data/` is out of scope for this loop.
/// `ChatController` needs to patch a handful of fields (streamed content,
/// terminal status/stats) without touching `data/`, so the copy helper lives
/// here instead. Re-exports `MessageRole`/`MessageStatus` (defined in
/// `data/db/database.dart`, a drift schema file `features/` otherwise never
/// imports per ADR-002) so callers get both from one place — `chat_export.
/// dart` (a `data/` file) already imports the enum the same narrow way.
library;

import '../../../data/chat/chat_repository.dart';
import '../../../data/db/database.dart' show MessageStatus;

export '../../../data/db/database.dart' show MessageRole, MessageStatus;

extension MessageInfoCopy on MessageInfo {
  MessageInfo copyWith({
    String? content,
    String? reasoningContent,
    bool clearReasoningContent = false,
    MessageStatus? status,
    String? errorKind,
    int? tokCount,
    int? genMs,
  }) {
    return MessageInfo(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      reasoningContent: clearReasoningContent
          ? null
          : (reasoningContent ?? this.reasoningContent),
      status: status ?? this.status,
      errorKind: errorKind ?? this.errorKind,
      tokCount: tokCount ?? this.tokCount,
      genMs: genMs ?? this.genMs,
      createdAt: createdAt,
      parentMessageId: parentMessageId,
    );
  }
}
