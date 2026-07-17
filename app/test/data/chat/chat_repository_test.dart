import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ChatRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChatRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('folders', () {
    test('create, rename, list ordered by sortIndex', () async {
      final b = await repo.createFolder('B');
      final a = await repo.createFolder('A');
      // Both default to sortIndex 0 — push `a` ahead of `b` explicitly
      // (repository has no reorder method yet; that's a features/chat UI
      // concern, this just proves listFolders honors the column).
      await (db.update(db.folders)..where((t) => t.id.equals(a))).write(
        const FoldersCompanion(sortIndex: Value(-1)),
      );

      final folders = await repo.listFolders();
      expect(folders.map((f) => f.id), [a, b]);

      await repo.renameFolder(a, 'Archive');
      final renamed = await repo.listFolders();
      expect(renamed.firstWhere((f) => f.id == a).name, 'Archive');
    });

    test('renameFolder on a missing id throws StorageNotFoundFailure', () {
      expect(
        () => repo.renameFolder(999, 'x'),
        throwsA(isA<StorageNotFoundFailure>()),
      );
    });

    test(
      'deleting a folder un-files its conversations (FK setNull), does not delete them',
      () async {
        final folderId = await repo.createFolder('Work');
        final conversationId = await repo.createConversation(
          title: 'chat',
          folderId: folderId,
        );

        await repo.deleteFolder(folderId);

        final convo = await repo.getConversation(conversationId);
        expect(convo, isNotNull);
        expect(convo!.folderId, isNull);
      },
    );

    test('deleteFolder on a missing id throws StorageNotFoundFailure', () {
      expect(
        () => repo.deleteFolder(999),
        throwsA(isA<StorageNotFoundFailure>()),
      );
    });
  });

  group('conversations CRUD', () {
    test(
      'createConversation defaults and getConversation round-trip',
      () async {
        final id = await repo.createConversation();
        final convo = await repo.getConversation(id);
        expect(convo, isNotNull);
        expect(convo!.title, '');
        expect(convo.folderId, isNull);
        expect(convo.modelId, isNull);
        expect(convo.systemPrompt, '');
        expect(convo.samplingParams, const SamplingParams());
        expect(convo.pinned, isFalse);
      },
    );

    test('createConversation validates and persists sampling params', () async {
      final id = await repo.createConversation(
        samplingParams: const SamplingParams(temperature: 0.2, topK: 10),
      );
      final convo = await repo.getConversation(id);
      expect(convo!.samplingParams.temperature, 0.2);
      expect(convo.samplingParams.topK, 10);
    });

    test('createConversation rejects invalid sampling params', () {
      expect(
        () => repo.createConversation(
          samplingParams: const SamplingParams(temperature: 99),
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('getConversation returns null for a missing id', () async {
      expect(await repo.getConversation(999), isNull);
    });

    test(
      'createConversation persists and round-trips characterId (Loop 5)',
      () async {
        // Conversations.characterId is a real FK (onDelete: setNull) — the
        // referenced row has to exist under `PRAGMA foreign_keys = ON`
        // (set in AppDatabase.beforeOpen), so this inserts a minimal
        // Characters row directly rather than reaching for
        // CharacterRepository (a different data-layer file, out of scope
        // here).
        final now = DateTime.now();
        final characterId = await db
            .into(db.characters)
            .insert(
              CharactersCompanion.insert(
                name: 'Coach',
                personaSystemPrompt: 'Be encouraging.',
                createdAt: now,
                updatedAt: now,
              ),
            );
        final id = await repo.createConversation(characterId: characterId);
        final convo = await repo.getConversation(id);
        expect(convo!.characterId, characterId);
      },
    );

    test(
      'createConversation defaults characterId to null for an ordinary chat',
      () async {
        final id = await repo.createConversation();
        final convo = await repo.getConversation(id);
        expect(convo!.characterId, isNull);
      },
    );

    test('deleting a character un-sets conversations.characterId (FK setNull) '
        'but the conversation, its persisted systemPrompt, and its messages '
        'all survive — attack list #4: chat still works off the persisted '
        'system prompt in messages, not a live re-fetch of the (now-gone) '
        'character', () async {
      final now = DateTime.now();
      final characterId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Coach',
              personaSystemPrompt: 'Be an encouraging coach.',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final conversationId = await repo.createConversation(
        characterId: characterId,
        systemPrompt: 'Be an encouraging coach.',
      );
      await repo.appendMessage(
        conversationId: conversationId,
        role: MessageRole.assistant,
        content: 'Ready to crush it today?',
      );

      await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(characterId))).go();

      final convo = await repo.getConversation(conversationId);
      expect(convo, isNotNull);
      expect(convo!.characterId, isNull);
      // The persona text itself lives on Conversations.systemPrompt, a
      // plain column independent of the character row — deleting the
      // character doesn't touch it.
      expect(convo.systemPrompt, 'Be an encouraging coach.');
      final messages = await repo.getMessages(conversationId);
      expect(messages, hasLength(1));
      expect(messages.single.content, 'Ready to crush it today?');
    });

    test(
      'deleteConversation removes the row and cascades its messages',
      () async {
        final id = await repo.createConversation(title: 'gone');
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.user,
          content: 'hi',
        );

        await repo.deleteConversation(id);

        expect(await repo.getConversation(id), isNull);
        final messages = await db.select(db.messages).get();
        expect(messages, isEmpty);
      },
    );

    test(
      'deleteConversation on a missing id throws StorageNotFoundFailure',
      () {
        expect(
          () => repo.deleteConversation(999),
          throwsA(isA<StorageNotFoundFailure>()),
        );
      },
    );

    test(
      'renameConversation, setPinned, moveToFolder, setModel, setSystemPrompt',
      () async {
        final folderId = await repo.createFolder('F');
        final id = await repo.createConversation();

        await repo.renameConversation(id, 'New title');
        await repo.setPinned(id, true);
        await repo.moveToFolder(id, folderId);
        await repo.setSystemPrompt(id, 'Be concise.');

        final convo = await repo.getConversation(id);
        expect(convo!.title, 'New title');
        expect(convo.pinned, isTrue);
        expect(convo.folderId, folderId);
        expect(convo.systemPrompt, 'Be concise.');
      },
    );

    test('setSamplingParams validates before persisting', () async {
      final id = await repo.createConversation();
      await repo.setSamplingParams(id, const SamplingParams(topP: 0.1));
      expect((await repo.getConversation(id))!.samplingParams.topP, 0.1);

      expect(
        () => repo.setSamplingParams(id, const SamplingParams(topP: 5)),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test(
      'a mutation touches updatedAt (used by listConversations ordering)',
      () async {
        final id = await repo.createConversation();
        // Drift's default dateTime column stores unix *seconds* (see
        // database.dart / DriftDatabaseOptions), so two `DateTime.now()`
        // calls a few ms apart in the same wall-clock second would tie —
        // seed an old fixed timestamp directly instead of racing the
        // clock, which is both deterministic and instant.
        await (db.update(
          db.conversations,
        )..where((t) => t.id.equals(id))).write(
          ConversationsCompanion(updatedAt: Value(DateTime.utc(2020))),
        );

        await repo.renameConversation(id, 'touched');

        final after = (await repo.getConversation(id))!.updatedAt;
        expect(after.isAfter(DateTime.utc(2020)), isTrue);
      },
    );
  });

  group('listConversations ordering + folder filter', () {
    test('pinned first, then most-recently-updated first', () async {
      final oldId = await repo.createConversation(title: 'old');
      final newId = await repo.createConversation(title: 'new');
      final pinnedButOldId = await repo.createConversation(title: 'pinned');
      // Explicit, clearly-ordered timestamps — see the "touches updatedAt"
      // test above for why this doesn't rely on real-clock delays.
      await _setUpdatedAt(db, oldId, DateTime.utc(2020, 1, 1));
      await _setUpdatedAt(db, newId, DateTime.utc(2022, 1, 1));
      await _setUpdatedAt(db, pinnedButOldId, DateTime.utc(2019, 1, 1));
      await repo.setPinned(pinnedButOldId, true);

      final list = await repo.listConversations();
      expect(list.map((c) => c.id), [pinnedButOldId, newId, oldId]);
    });

    test('folderId filters to that folder only', () async {
      final folderId = await repo.createFolder('Work');
      final inFolder = await repo.createConversation(folderId: folderId);
      await repo.createConversation();

      final list = await repo.listConversations(folderId: folderId);
      expect(list.map((c) => c.id), [inFolder]);
    });

    test('onlyUnfiled returns conversations with no folder', () async {
      final folderId = await repo.createFolder('Work');
      await repo.createConversation(folderId: folderId);
      final unfiled = await repo.createConversation();

      final list = await repo.listConversations(onlyUnfiled: true);
      expect(list.map((c) => c.id), [unfiled]);
    });
  });

  group('messages + appendMessage + auto-title', () {
    test('appendMessage inserts and getMessages orders oldest first', () async {
      final id = await repo.createConversation();
      final m1 = await repo.appendMessage(
        conversationId: id,
        role: MessageRole.user,
        content: 'hi',
      );
      final m2 = await repo.appendMessage(
        conversationId: id,
        role: MessageRole.assistant,
        content: 'hello',
      );

      final messages = await repo.getMessages(id);
      expect(messages.map((m) => m.id), [m1, m2]);
      expect(messages[0].role, MessageRole.user);
      expect(messages[1].role, MessageRole.assistant);
    });

    test(
      'appendMessage auto-titles an empty-title conversation from the first user message',
      () async {
        final id = await repo.createConversation();
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.user,
          content: 'What is the capital of France?',
        );

        final convo = await repo.getConversation(id);
        expect(convo!.title, 'What is the capital of France?');
      },
    );

    test('auto-title truncates to ~40 chars with an ellipsis', () async {
      final id = await repo.createConversation();
      final longMessage = 'x' * 100;
      await repo.appendMessage(
        conversationId: id,
        role: MessageRole.user,
        content: longMessage,
      );

      final convo = await repo.getConversation(id);
      expect(convo!.title, '${'x' * 40}…');
    });

    test('auto-title does not overwrite an existing title', () async {
      final id = await repo.createConversation(title: 'Keep me');
      await repo.appendMessage(
        conversationId: id,
        role: MessageRole.user,
        content: 'ignored for title',
      );
      expect((await repo.getConversation(id))!.title, 'Keep me');
    });

    test('auto-title does not fire on an assistant message', () async {
      final id = await repo.createConversation();
      await repo.appendMessage(
        conversationId: id,
        role: MessageRole.assistant,
        content: 'a system-initiated greeting',
      );
      expect((await repo.getConversation(id))!.title, '');
    });

    test('finalize sets terminal status/stats and touches updatedAt', () async {
      final id = await repo.createConversation();
      final messageId = await repo.appendMessage(
        conversationId: id,
        role: MessageRole.assistant,
        status: MessageStatus.complete,
      );
      await _setUpdatedAt(db, id, DateTime.utc(2020));

      await repo.finalize(
        messageId,
        status: MessageStatus.error,
        errorKind: 'EngineDecodeFailure',
        tokCount: 12,
        genMs: 340,
      );

      final messages = await repo.getMessages(id);
      final message = messages.single;
      expect(message.status, MessageStatus.error);
      expect(message.errorKind, 'EngineDecodeFailure');
      expect(message.tokCount, 12);
      expect(message.genMs, 340);
      expect(
        (await repo.getConversation(id))!.updatedAt.isAfter(DateTime.utc(2020)),
        isTrue,
      );
    });

    test('finalize on a missing message throws StorageNotFoundFailure', () {
      expect(
        () => repo.finalize(999, status: MessageStatus.complete),
        throwsA(isA<StorageNotFoundFailure>()),
      );
    });

    test(
      'parentMessageId links a regenerated message back to the one it replaced',
      () async {
        final id = await repo.createConversation();
        final original = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
          content: 'first answer',
        );
        final regenerated = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
          content: 'better answer',
          parentMessageId: original,
        );

        final messages = await repo.getMessages(id);
        expect(
          messages.firstWhere((m) => m.id == regenerated).parentMessageId,
          original,
        );
      },
    );
  });

  group('updateStreamingMessage', () {
    test(
      'appends content deltas without clobbering existing content',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
        );

        await repo.updateStreamingMessage(messageId, contentDelta: 'Hel');
        await repo.updateStreamingMessage(messageId, contentDelta: 'lo');
        await repo.updateStreamingMessage(messageId, contentDelta: ' world');

        final message = (await repo.getMessages(id)).single;
        expect(message.content, 'Hello world');
      },
    );

    test('appends reasoning deltas independently of content deltas', () async {
      final id = await repo.createConversation();
      final messageId = await repo.appendMessage(
        conversationId: id,
        role: MessageRole.assistant,
      );

      await repo.updateStreamingMessage(
        messageId,
        contentDelta: 'answer',
        reasoningDelta: 'thinking...',
      );
      await repo.updateStreamingMessage(messageId, reasoningDelta: ' more.');

      final message = (await repo.getMessages(id)).single;
      expect(message.content, 'answer');
      expect(message.reasoningContent, 'thinking... more.');
    });

    test(
      'reasoningContent stays null when no reasoning delta was ever sent',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
        );

        await repo.updateStreamingMessage(messageId, contentDelta: 'plain');

        final message = (await repo.getMessages(id)).single;
        expect(message.reasoningContent, isNull);
      },
    );

    test(
      'a call with no deltas is a no-op (does not throw, does not touch the row)',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
          content: 'unchanged',
        );
        await repo.updateStreamingMessage(messageId);
        expect((await repo.getMessages(id)).single.content, 'unchanged');
      },
    );

    test(
      'streaming-update efficiency: 200 back-to-back per-token calls complete '
      'well under budget, supporting a per-call (non-batched) write strategy '
      '— see ChatRepository.updateStreamingMessage doc comment',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
        );

        const tokenCount = 200;
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < tokenCount; i++) {
          await repo.updateStreamingMessage(messageId, contentDelta: 'a');
        }
        stopwatch.stop();

        expect((await repo.getMessages(id)).single.content, 'a' * tokenCount);
        // Generous budget for a debug/CI-slow machine: even 5ms/call (50x
        // this box's measured cost) would be invisible against real
        // llama.cpp decode latency (10-20ms/token). Catches an accidental
        // full-table-scan-per-update regression, not micro-timing noise.
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(tokenCount * 5),
          reason:
              'per-call UPDATE took '
              '${stopwatch.elapsedMilliseconds / tokenCount}ms/call on average',
        );
      },
    );
  });

  group('setStreamingContent', () {
    test(
      'overwrites content/reasoningContent absolutely, not appending',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
        );
        await repo.updateStreamingMessage(
          messageId,
          contentDelta: 'stale prefix',
          reasoningDelta: 'stale reasoning',
        );

        await repo.setStreamingContent(
          messageId,
          content: 'corrected content',
          reasoningContent: 'corrected reasoning',
        );

        final message = (await repo.getMessages(id)).single;
        expect(message.content, 'corrected content');
        expect(message.reasoningContent, 'corrected reasoning');
      },
    );

    test(
      'a null reasoningContent clears the column rather than leaving the '
      'old value in place (unlike updateStreamingMessage\'s COALESCE-and-'
      'append path — this call means "make the row match exactly")',
      () async {
        final id = await repo.createConversation();
        final messageId = await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
        );
        await repo.updateStreamingMessage(
          messageId,
          reasoningDelta: 'will be cleared',
        );

        await repo.setStreamingContent(messageId, content: 'plain answer');

        final message = (await repo.getMessages(id)).single;
        expect(message.content, 'plain answer');
        expect(message.reasoningContent, isNull);
      },
    );
  });

  group('search', () {
    test('matches on conversation title', () async {
      final id = await repo.createConversation(title: 'Trip to Paris');
      await repo.createConversation(title: 'Grocery list');

      final hits = await repo.search('paris');
      expect(hits.map((h) => h.conversationId), [id]);
      expect(hits.single.snippet, 'Trip to Paris');
    });

    test('matches on message content and returns a snippet', () async {
      final id = await repo.createConversation(title: 'Untitled chat');
      await repo.appendMessage(
        conversationId: id,
        role: MessageRole.user,
        content: 'How do I bake sourdough bread at home?',
      );

      final hits = await repo.search('sourdough');
      expect(hits, hasLength(1));
      expect(hits.single.conversationId, id);
      expect(hits.single.snippet, contains('sourdough'));
    });

    test('is case-insensitive', () async {
      final id = await repo.createConversation(title: 'CAPS LOCK');
      final hits = await repo.search('caps lock');
      expect(hits.map((h) => h.conversationId), [id]);
    });

    test(
      'a conversation matching in both title and a message appears once',
      () async {
        final id = await repo.createConversation(title: 'apple pie recipe');
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.user,
          content: 'apple pie needs apples',
        );
        final hits = await repo.search('apple');
        expect(hits, hasLength(1));
      },
    );

    test(
      'percent and underscore in the query are treated literally, not as wildcards',
      () async {
        await repo.createConversation(title: '50% off sale');
        await repo.createConversation(title: 'totally unrelated');

        final hits = await repo.search('50%');
        expect(hits, hasLength(1));
      },
    );

    test('no matches returns an empty list', () async {
      await repo.createConversation(title: 'something');
      expect(await repo.search('nonexistent-term-xyz'), isEmpty);
    });

    test('blank query returns an empty list without hitting the db', () async {
      expect(await repo.search('   '), isEmpty);
    });
  });

  group('export', () {
    test(
      'exportConversationMarkdown includes title, role sections, and reasoning as details',
      () async {
        final id = await repo.createConversation(title: 'Export me');
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.user,
          content: 'question',
        );
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.assistant,
          content: 'answer',
          reasoningContent: 'thinking it through',
        );

        final markdown = await repo.exportConversationMarkdown(id);
        expect(markdown, contains('# Export me'));
        expect(markdown, contains('## User'));
        expect(markdown, contains('question'));
        expect(markdown, contains('## Assistant'));
        expect(markdown, contains('<details>'));
        expect(markdown, contains('thinking it through'));
        expect(markdown, contains('answer'));
      },
    );

    test(
      'exportConversationJson has version:1 and round-trips message data',
      () async {
        final id = await repo.createConversation(title: 'Export me');
        await repo.appendMessage(
          conversationId: id,
          role: MessageRole.user,
          content: 'question',
          status: MessageStatus.complete,
        );

        final json = await repo.exportConversationJson(id);
        expect(json, contains('"version": 1'));
        expect(json, contains('"title": "Export me"'));
        expect(json, contains('"role": "user"'));
        expect(json, contains('"content": "question"'));
      },
    );

    test('export on a missing conversation throws StorageNotFoundFailure', () {
      expect(
        () => repo.exportConversationMarkdown(999),
        throwsA(isA<StorageNotFoundFailure>()),
      );
    });

    test('export includes the model label when modelId resolves', () async {
      final modelId = await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
              fileName: 'x.gguf',
              quant: const Value('Q4_K_M'),
              sizeBytes: 1,
              localPath: '/models/x.gguf',
              downloadedAt: DateTime.utc(2026, 7, 17),
            ),
          );
      final id = await repo.createConversation(
        title: 'With model',
        modelId: modelId,
      );

      final markdown = await repo.exportConversationMarkdown(id);
      expect(markdown, contains('bartowski/Llama-3.2-1B-Instruct-GGUF'));
      expect(markdown, contains('Q4_K_M'));
    });

    test(
      'export shows no model line after the model is deleted (modelId FK setNull)',
      () async {
        final modelId = await db
            .into(db.installedModels)
            .insert(
              InstalledModelsCompanion.insert(
                repoId: 'r/m',
                fileName: 'x.gguf',
                sizeBytes: 1,
                localPath: '/models/x.gguf',
                downloadedAt: DateTime.utc(2026, 7, 17),
              ),
            );
        final id = await repo.createConversation(modelId: modelId);
        await (db.delete(
          db.installedModels,
        )..where((t) => t.id.equals(modelId))).go();

        final convo = await repo.getConversation(id);
        expect(convo!.modelId, isNull);

        final markdown = await repo.exportConversationMarkdown(id);
        expect(markdown, contains('No model'));
      },
    );
  });

  group('QA (Loop-4 attack list #4): 1000-message conversation load', () {
    test('getMessages on a 1000-message conversation is a full eager load — '
        'no LIMIT/pagination — measured, not assumed', () async {
      final id = await repo.createConversation();
      // Bulk-insert directly (bypassing appendMessage's per-call
      // renameAuto/touchUpdatedAt round trips — this test is about the
      // read path's cost, not simulating 1000 real sends).
      await db.batch((batch) {
        batch.insertAll(db.messages, [
          for (var i = 0; i < 1000; i++)
            MessagesCompanion.insert(
              conversationId: id,
              role: i.isEven ? MessageRole.user : MessageRole.assistant,
              content: Value('message number $i'),
              status: MessageStatus.complete,
              createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
            ),
        ]);
      });

      final sw = Stopwatch()..start();
      final messages = await repo.getMessages(id);
      sw.stop();

      // Confirms it IS a full, unpaginated load (every row comes back)...
      expect(messages, hasLength(1000));
      expect(messages.first.content, 'message number 0');
      expect(messages.last.content, 'message number 999');
      // ...and judges the cost: on an in-memory db, indexed by
      // idx_messages_conversation, this is comfortably sub-100ms — a
      // single-user on-device chat history doesn't need pagination at
      // this row count (matches the repository's own class-doc rationale
      // for skipping FTS5). Not a hard perf budget, a sanity ceiling.
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('clearAllHistory', () {
    test('deletes every conversation and cascades to its messages', () async {
      final modelId = await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'r/m',
              fileName: 'x.gguf',
              sizeBytes: 1,
              localPath: '/models/x.gguf',
              downloadedAt: DateTime.utc(2026, 7, 17),
            ),
          );
      final a = await repo.createConversation(modelId: modelId);
      final b = await repo.createConversation();
      await repo.appendMessage(
        conversationId: a,
        role: MessageRole.user,
        content: 'hi',
      );
      await repo.appendMessage(
        conversationId: b,
        role: MessageRole.user,
        content: 'hey',
      );

      await repo.clearAllHistory();

      expect(await repo.listConversations(), isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
      // Installed models are untouched — only conversations/messages are in
      // scope for this action.
      expect(await db.select(db.installedModels).get(), hasLength(1));
    });

    test('an active download in flight is untouched — clearAllHistory only '
        'issues DELETE FROM conversations, a disjoint table from anything '
        'DownloadManager tracks', () async {
      final modelsDir = Directory.systemTemp.createTempSync(
        'dhruva_clear_history_downloads_test_',
      );
      addTearDown(() {
        if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
      });
      final backend = FakeDownloadBackend();
      final manager = DownloadManager(
        backend: backend,
        db: db,
        modelsDirectory: modelsDir,
      );
      addTearDown(manager.dispose);

      final request = DownloadRequest(
        repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
        fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
        url: Uri.parse('https://huggingface.co/x/resolve/main/x.gguf'),
        expectedSizeBytes: 5,
      );

      final progressEvents = <DownloadProgress>[];
      final sub = manager.progress.listen(progressEvents.add);
      addTearDown(sub.cancel);

      await manager.enqueue(request, freeBytes: 1 << 30);
      await repo.createConversation(title: 'unrelated chat');

      await repo.clearAllHistory();

      // The conversation is gone...
      expect(await repo.listConversations(), isEmpty);
      // ...but the in-flight download is still tracked and keeps
      // forwarding backend updates — proving DownloadManager's state
      // wasn't reset or corrupted by an unrelated table's DELETE.
      backend.emit(
        BackendProgressUpdate(
          request.taskId,
          progress: 0.5,
          expectedFileSizeBytes: request.expectedSizeBytes,
        ),
      );
      await pumpEventQueue();
      expect(
        progressEvents.any(
          (e) => e.taskId == request.taskId && e.state == DownloadState.running,
        ),
        isTrue,
      );
    });
  });
}

/// Test-only direct write, bypassing the repository's `DateTime.now()` —
/// see the "touches updatedAt" test for why.
Future<void> _setUpdatedAt(AppDatabase db, int conversationId, DateTime dt) {
  return (db.update(db.conversations)
        ..where((t) => t.id.equals(conversationId)))
      .write(ConversationsCompanion(updatedAt: Value(dt)));
}
