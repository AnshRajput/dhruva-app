import 'dart:convert';

import '../db/database.dart' show MessageRole;
import 'chat_repository.dart' show MessageInfo;

/// A conversation's messages plus enough metadata to export it. Pure input
/// for [formatConversationMarkdown]/[formatConversationJson] — no db
/// handle, no I/O — so `ChatRepository.exportConversation*` (which fetches
/// this from drift) and the formatters themselves can be tested
/// separately: golden-string tests exercise the formatters directly with a
/// hand-built [ChatExportData], no database involved.
final class ChatExportData {
  final String title;

  /// `null` when the conversation has no model set, or the model it used
  /// has since been deleted (`Conversations.modelId` FKs `setNull`).
  final String? modelLabel;
  final DateTime createdAt;
  final List<MessageInfo> messages;

  const ChatExportData({
    required this.title,
    this.modelLabel,
    required this.createdAt,
    required this.messages,
  });
}

String _roleLabel(MessageRole role) => switch (role) {
  MessageRole.user => 'User',
  MessageRole.assistant => 'Assistant',
  MessageRole.system => 'System',
};

/// title header, metadata line, role-labeled sections, reasoning as a
/// collapsible `<details>` block (renders fine on GitHub/most MD viewers,
/// degrades to plain visible text elsewhere), code fences passed through
/// verbatim (never re-escaped).
String formatConversationMarkdown(ChatExportData data) {
  final buffer = StringBuffer()
    ..writeln('# ${data.title}')
    ..writeln()
    ..writeln(
      '_${data.modelLabel ?? 'No model'} · ${data.createdAt.toIso8601String()}_',
    );

  for (final message in data.messages) {
    buffer
      ..writeln()
      ..writeln('## ${_roleLabel(message.role)}');
    final reasoning = message.reasoningContent;
    if (reasoning != null && reasoning.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('<details>')
        ..writeln('<summary>Reasoning</summary>')
        ..writeln()
        ..writeln(reasoning)
        ..writeln()
        ..writeln('</details>');
    }
    buffer
      ..writeln()
      ..writeln(message.content);
  }
  return buffer.toString();
}

/// `{version: 1, ...}` — stable, additive-only shape. Bump `version` (and
/// keep reading old ones) before ever removing/renaming a field.
String formatConversationJson(ChatExportData data) {
  final json = {
    'version': 1,
    'title': data.title,
    'model': data.modelLabel,
    'createdAt': data.createdAt.toIso8601String(),
    'messages': [
      for (final m in data.messages)
        {
          'role': m.role.name,
          'content': m.content,
          if (m.reasoningContent != null)
            'reasoningContent': m.reasoningContent,
          'status': m.status.name,
          if (m.errorKind != null) 'errorKind': m.errorKind,
          if (m.tokCount != null) 'tokCount': m.tokCount,
          if (m.genMs != null) 'genMs': m.genMs,
          'createdAt': m.createdAt.toIso8601String(),
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(json);
}
