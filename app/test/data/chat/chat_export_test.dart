import 'dart:convert';

import 'package:dhruva/data/chat/chat_export.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 7, 17, 12, 30);

  MessageInfo message({
    required int id,
    required MessageRole role,
    required String content,
    String? reasoningContent,
    MessageStatus status = MessageStatus.complete,
    String? errorKind,
    int? tokCount,
    int? genMs,
  }) => MessageInfo(
    id: id,
    conversationId: 1,
    role: role,
    content: content,
    reasoningContent: reasoningContent,
    status: status,
    errorKind: errorKind,
    tokCount: tokCount,
    genMs: genMs,
    createdAt: createdAt,
  );

  group('formatConversationMarkdown', () {
    test('exact output for a simple exchange (no reasoning)', () {
      final data = ChatExportData(
        title: 'Capital of France',
        modelLabel: 'bartowski/Llama-3.2-1B-Instruct-GGUF (Q4_K_M)',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.user,
            content: 'What is the capital of France?',
          ),
          message(id: 2, role: MessageRole.assistant, content: 'Paris.'),
        ],
      );

      expect(
        formatConversationMarkdown(data),
        '# Capital of France\n'
        '\n'
        '_bartowski/Llama-3.2-1B-Instruct-GGUF (Q4_K_M) · ${createdAt.toIso8601String()}_\n'
        '\n'
        '## User\n'
        '\n'
        'What is the capital of France?\n'
        '\n'
        '## Assistant\n'
        '\n'
        'Paris.\n',
      );
    });

    test('exact output with a reasoning block as a collapsible <details>', () {
      final data = ChatExportData(
        title: 'Reasoning demo',
        modelLabel: null,
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.assistant,
            content: 'The answer is 4.',
            reasoningContent: '2 + 2 = 4.',
          ),
        ],
      );

      expect(
        formatConversationMarkdown(data),
        '# Reasoning demo\n'
        '\n'
        '_No model · ${createdAt.toIso8601String()}_\n'
        '\n'
        '## Assistant\n'
        '\n'
        '<details>\n'
        '<summary>Reasoning</summary>\n'
        '\n'
        '2 + 2 = 4.\n'
        '\n'
        '</details>\n'
        '\n'
        'The answer is 4.\n',
      );
    });

    test('code fences pass through unescaped', () {
      final data = ChatExportData(
        title: 'Code',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.assistant,
            content: '```dart\nprint("hi");\n```',
          ),
        ],
      );

      expect(
        formatConversationMarkdown(data),
        contains('```dart\nprint("hi");\n```'),
      );
    });

    test('system role is labeled "## System"', () {
      final data = ChatExportData(
        title: 't',
        createdAt: createdAt,
        messages: [
          message(id: 1, role: MessageRole.system, content: 'Be concise.'),
        ],
      );
      expect(formatConversationMarkdown(data), contains('## System'));
    });
  });

  group('formatConversationJson', () {
    test('exact output shape (version, metadata, one message)', () {
      final data = ChatExportData(
        title: 'Capital of France',
        modelLabel: 'bartowski/Llama-3.2-1B-Instruct-GGUF (Q4_K_M)',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.assistant,
            content: 'Paris.',
            tokCount: 3,
            genMs: 120,
          ),
        ],
      );

      expect(
        formatConversationJson(data),
        '{\n'
        '  "version": 1,\n'
        '  "title": "Capital of France",\n'
        '  "model": "bartowski/Llama-3.2-1B-Instruct-GGUF (Q4_K_M)",\n'
        '  "createdAt": "${createdAt.toIso8601String()}",\n'
        '  "messages": [\n'
        '    {\n'
        '      "role": "assistant",\n'
        '      "content": "Paris.",\n'
        '      "status": "complete",\n'
        '      "tokCount": 3,\n'
        '      "genMs": 120,\n'
        '      "createdAt": "${createdAt.toIso8601String()}"\n'
        '    }\n'
        '  ]\n'
        '}',
      );
    });

    test('model is JSON null when there is none', () {
      final data = ChatExportData(
        title: 't',
        createdAt: createdAt,
        messages: const [],
      );
      expect(formatConversationJson(data), contains('"model": null'));
    });

    test(
      'optional fields (reasoningContent, errorKind, tokCount, genMs) are omitted when null',
      () {
        final data = ChatExportData(
          title: 't',
          createdAt: createdAt,
          messages: [message(id: 1, role: MessageRole.user, content: 'hi')],
        );
        final json = formatConversationJson(data);
        expect(json, isNot(contains('reasoningContent')));
        expect(json, isNot(contains('errorKind')));
        expect(json, isNot(contains('tokCount')));
        expect(json, isNot(contains('genMs')));
      },
    );

    test('an error message includes status and errorKind', () {
      final data = ChatExportData(
        title: 't',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.assistant,
            content: '',
            status: MessageStatus.error,
            errorKind: 'EngineDecodeFailure',
          ),
        ],
      );
      final json = formatConversationJson(data);
      expect(json, contains('"status": "error"'));
      expect(json, contains('"errorKind": "EngineDecodeFailure"'));
    });
  });

  // QA (Loop-7 TEST, attack 5 "vision + existing features" — export):
  // `ChatExportData`/`MessageInfo` carry no image field at all — Loop 7's
  // attached-image bytes live only in `ChatThreadState.attachedImages`
  // (session-only, chat_controller.dart's own doc), and
  // `chat_thread_screen.dart`'s `_export` calls `ChatRepository.
  // exportConversationMarkdown/Json(conversationId)` directly from the
  // repo, never through the controller — so an exported conversation
  // structurally CANNOT know a message had an image attached. Confirmed
  // here: exporting a user message whose text WAS the vision "extract
  // text" preset produces clean output with zero trace an image was ever
  // involved. Not a crash, not corrupted data — but a silent, permanent
  // loss of context in the exported artifact (worst case: an
  // "Extract text" exchange exports as a question with no visible
  // question and an answer with no image to explain what it's answering
  // about). Filed as a QA BUG, low/medium severity — export is a real
  // chat-spec.md §9 feature, and nothing tells the user their export is
  // incomplete.
  group('QA BUG: image attachments are silently absent from export', () {
    test('markdown export of an image-attached exchange has no mention of '
        'an image', () {
      final data = ChatExportData(
        title: 'Photo Q&A',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.user,
            content: 'What is the main color of this image?',
          ),
          message(id: 2, role: MessageRole.assistant, content: 'Red.'),
        ],
      );
      final md = formatConversationMarkdown(data);
      expect(md, contains('What is the main color of this image?'));
      expect(md, contains('Red.'));
      // Documents the gap: no [image]/attachment marker of any kind.
      expect(md.toLowerCase(), isNot(contains('attach')));
      expect(md.toLowerCase(), isNot(contains('[image')));
    });

    test('JSON export has no image/attachment field on the message at all', () {
      final data = ChatExportData(
        title: 'Photo Q&A',
        createdAt: createdAt,
        messages: [
          // This is the vision "extract text" preset's actual wording
          // (vision_presets.dart's extractTextPrompt), inlined rather than
          // imported to keep this data/-layer test's imports pointed only
          // at data/ (ADR-002's features -> data -> core direction). The
          // check below inspects JSON *keys*, not content, so the word
          // "image" appearing in the message text itself doesn't matter.
          message(
            id: 1,
            role: MessageRole.user,
            content: 'Extract all text from this image, output only the text',
          ),
        ],
      );
      final decoded =
          jsonDecode(formatConversationJson(data)) as Map<String, dynamic>;
      final msgKeys = (decoded['messages'] as List)
          .cast<Map<String, dynamic>>()
          .single
          .keys;
      expect(
        msgKeys,
        isNot(anyElement(contains('image'))),
        reason: 'no field carries the fact this turn had an image attached',
      );
      expect(msgKeys, isNot(anyElement(contains('attach'))));
    });
  });
}
