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

  // QA LOW FIXED (Loop-7 export): attached-image bytes are session-only
  // (`ChatThreadState.attachedImages`), so the export still can't embed the
  // picture — but `chat_thread_screen.dart`'s `_export` now passes the live
  // set of message ids that had an image (`imageMessageIds`) into the export,
  // so the context isn't dropped silently. A `[image attached]` marker lands
  // in both the markdown and JSON for those messages, and messages with no
  // image (or an export in a later session where the map is empty) are
  // unchanged.
  group('QA LOW FIXED: image attachments are marked in export', () {
    test('markdown export marks an image-attached message with '
        '[image attached]', () {
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
        imageMessageIds: const {1},
      );
      final md = formatConversationMarkdown(data);
      expect(md, contains('What is the main color of this image?'));
      expect(md, contains('Red.'));
      expect(md, contains('[image attached]'));
      // The marker sits under the user turn (which had the image), not the
      // assistant reply.
      final userSection = md.substring(
        md.indexOf('## User'),
        md.indexOf('## Assistant'),
      );
      expect(userSection, contains('[image attached]'));
    });

    test('markdown export without imageMessageIds has no marker (later-session '
        'export or a text-only exchange)', () {
      final data = ChatExportData(
        title: 'Photo Q&A',
        createdAt: createdAt,
        messages: [
          message(id: 1, role: MessageRole.user, content: 'Hello there'),
        ],
      );
      expect(formatConversationMarkdown(data), isNot(contains('[image')));
    });

    test('JSON export sets imageAttached:true on the image-bearing message '
        'only', () {
      final data = ChatExportData(
        title: 'Photo Q&A',
        createdAt: createdAt,
        messages: [
          message(
            id: 1,
            role: MessageRole.user,
            content: 'Extract all text from this image, output only the text',
          ),
          message(id: 2, role: MessageRole.assistant, content: 'CAT'),
        ],
        imageMessageIds: const {1},
      );
      final decoded =
          jsonDecode(formatConversationJson(data)) as Map<String, dynamic>;
      final messages = (decoded['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages[0]['imageAttached'], true);
      expect(messages[1].containsKey('imageAttached'), isFalse);
    });
  });
}
