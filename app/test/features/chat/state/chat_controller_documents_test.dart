import 'dart:async';
import 'dart:typed_data';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/docs/document_picker.dart';
import 'package:dhruva/docs/fake_document_picker.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late FakeDocumentPicker picker;
  late FakeEngineService engine;
  var failExtract = false;

  /// When set, the fake extractor waits on it (a read that is still running).
  Completer<void>? gate;

  setUp(() {
    gate = null;
    db = AppDatabase(NativeDatabase.memory());
    picker = FakeDocumentPicker()
      ..next = const PickedDocument(name: 'terms.txt', path: '/fake/terms.txt');
    engine = FakeEngineService(
      scriptedTokens: const ['Two years ', '[p.2].'],
      tokenDelay: const Duration(milliseconds: 5),
    );
    failExtract = false;
  });

  tearDown(() async {
    // `finalize`/`setSources` are fire-and-forget in the controller; let them
    // land before the in-memory DB closes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'bartowski/Some-Model-GGUF',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/dhruva-test-model.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  // Synchronous stand-in for the isolate extractor.
  Future<ExtractedDocument> fakeExtract(String path, String name) async {
    await gate?.future;
    if (failExtract) {
      throw const DocumentException(
        DocumentFailureKind.noText,
        'This PDF has no selectable text.',
      );
    }
    return extractDocumentBytes(
      Uint8List.fromList(
        (StringBuffer()
              ..write('Intro paragraph about the project. ' * 30)
              ..write('\n\n')
              ..write('The warranty lasts two years and covers parts. ' * 60))
            .toString()
            .codeUnits,
      ),
      name,
    );
  }

  ProviderContainer build() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        documentPickerProvider.overrideWithValue(picker),
        documentExtractorProvider.overrideWithValue(fakeExtract),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ChatController> open(ProviderContainer c, ChatRouteArgs args) async {
    await c.read(chatControllerProvider(args).future);
    c.listen(chatControllerProvider(args), (_, _) {});
    return c.read(chatControllerProvider(args).notifier);
  }

  ChatThreadState stateOf(ProviderContainer c, ChatRouteArgs args) =>
      c.read(chatControllerProvider(args)).value!;

  test('Cancel on the Reading chip clears it and attaches nothing when the '
      'read finishes', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    gate = Completer<void>();

    final reading = ctrl.attachDocument();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stateOf(c, args).extractingDocName, 'terms.txt');

    ctrl.cancelDocumentRead();
    expect(stateOf(c, args).extractingDocName, isNull);

    gate!.complete(); // the isolate finishes after all
    await reading;
    final s = stateOf(c, args);
    expect(s.documents, isEmpty);
    expect(s.extractingDocName, isNull);
    expect(s.documentError, isNull);

    // And the user can attach again straight away.
    gate = null;
    await ctrl.attachDocument();
    expect(stateOf(c, args).documents, hasLength(1));
  });

  test('Cancel with nothing being read does nothing', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    ctrl.cancelDocumentRead();
    expect(stateOf(c, args).extractingDocName, isNull);
  });

  test(
    'a draft chat holds the document, then stores it on first send',
    () async {
      final modelId = await insertModel();
      final args = ChatRouteArgs(initialModelId: modelId);
      final c = build();
      final ctrl = await open(c, args);

      await ctrl.attachDocument();
      var s = stateOf(c, args);
      expect(s.documents, hasLength(1));
      expect(s.documents.single.name, 'terms.txt');
      expect(
        s.documents.single.id,
        lessThan(0),
      ); // pending, no conversation yet
      expect(s.extractingDocName, isNull);
      expect(await db.select(db.attachedDocuments).get(), isEmpty);

      await ctrl.sendMessage('How long is the warranty?');
      s = stateOf(c, args);
      expect(s.conversationId, isNotNull);
      expect(s.documents.single.id, greaterThan(0));
      final stored = await db.select(db.attachedDocuments).get();
      expect(stored.single.conversationId, s.conversationId);
      expect(await db.select(db.documentChunks).get(), isNotEmpty);
    },
  );

  test('the question reaches the model grounded in excerpts, but the stored '
      'message keeps the user words', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    await ctrl.attachDocument();
    await ctrl.sendMessage('How long is the warranty?');

    final userTurn = engine.lastMessages!.lastWhere(
      (t) => t.role == EngineRole.user,
    );
    expect(userTurn.content, contains('only the document excerpts'));
    expect(userTurn.content, contains('The warranty lasts two years'));
    expect(userTurn.content, contains('Question: How long is the warranty?'));

    final s = stateOf(c, args);
    final user = s.messages.firstWhere((m) => m.role == MessageRole.user);
    expect(user.content, 'How long is the warranty?');
  });

  test(
    'the grounded reply records its cited sources (and persists them)',
    () async {
      final modelId = await insertModel();
      final args = ChatRouteArgs(initialModelId: modelId);
      final c = build();
      final ctrl = await open(c, args);
      await ctrl.attachDocument();
      await ctrl.sendMessage('How long is the warranty?');

      final reply = stateOf(c, args).messages.last;
      expect(reply.role, MessageRole.assistant);
      expect(reply.sources, isNotEmpty);
      expect(reply.sources.first.docName, 'terms.txt');

      // Reopening the conversation from the DB shows the same Sources.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final reopenArgs = ChatRouteArgs(
        conversationId: stateOf(c, args).conversationId,
      );
      await open(c, reopenArgs);
      final reopened = stateOf(c, reopenArgs);
      expect(reopened.messages.last.sources, isNotEmpty);
      expect(reopened.documents.single.name, 'terms.txt');
    },
  );

  test(
    'a chat with no document sends the plain question and no sources',
    () async {
      final modelId = await insertModel();
      final args = ChatRouteArgs(initialModelId: modelId);
      final c = build();
      final ctrl = await open(c, args);
      await ctrl.sendMessage('hello there');
      final userTurn = engine.lastMessages!.lastWhere(
        (t) => t.role == EngineRole.user,
      );
      expect(userTurn.content, 'hello there');
      expect(stateOf(c, args).messages.last.sources, isEmpty);
    },
  );

  test('removing a document stops grounding and deletes its text', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    await ctrl.attachDocument();
    await ctrl.sendMessage('first question');
    final docId = stateOf(c, args).documents.single.id;

    await ctrl.removeDocument(docId);
    expect(stateOf(c, args).documents, isEmpty);
    expect(await db.select(db.attachedDocuments).get(), isEmpty);
    expect(await db.select(db.documentChunks).get(), isEmpty);

    await ctrl.sendMessage('second question');
    final userTurn = engine.lastMessages!.lastWhere(
      (t) => t.role == EngineRole.user,
    );
    expect(userTurn.content, 'second question');
  });

  test(
    'removing a pending draft document never touches the database',
    () async {
      final modelId = await insertModel();
      final args = ChatRouteArgs(initialModelId: modelId);
      final c = build();
      final ctrl = await open(c, args);
      await ctrl.attachDocument();
      await ctrl.removeDocument(stateOf(c, args).documents.single.id);
      expect(stateOf(c, args).documents, isEmpty);
      await ctrl.sendMessage('hello');
      expect(await db.select(db.attachedDocuments).get(), isEmpty);
    },
  );

  test(
    'an extraction failure surfaces its message and can be dismissed',
    () async {
      final modelId = await insertModel();
      final args = ChatRouteArgs(initialModelId: modelId);
      final c = build();
      final ctrl = await open(c, args);
      failExtract = true;
      await ctrl.attachDocument();
      var s = stateOf(c, args);
      expect(s.documents, isEmpty);
      expect(s.documentError, 'This PDF has no selectable text.');
      expect(s.extractingDocName, isNull);
      ctrl.dismissDocumentError();
      s = stateOf(c, args);
      expect(s.documentError, isNull);
    },
  );

  test('cancelling the picker changes nothing', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    picker.next = null;
    await ctrl.attachDocument();
    final s = stateOf(c, args);
    expect(picker.pickCount, 1);
    expect(s.documents, isEmpty);
    expect(s.documentError, isNull);
  });

  test('attaching beyond the limit is refused with a clear message', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    for (var i = 0; i < ChatController.maxDocuments; i++) {
      await ctrl.attachDocument();
    }
    expect(stateOf(c, args).documents, hasLength(ChatController.maxDocuments));
    await ctrl.attachDocument();
    final s = stateOf(c, args);
    expect(s.documents, hasLength(ChatController.maxDocuments));
    expect(s.documentError, contains('up to ${ChatController.maxDocuments}'));
  });

  test('deleting the conversation deletes its documents and chunks', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    await ctrl.attachDocument();
    await ctrl.sendMessage('hello');
    expect(await db.select(db.documentChunks).get(), isNotEmpty);

    await c
        .read(chatRepositoryProvider)
        .deleteConversation(stateOf(c, args).conversationId!);
    expect(await db.select(db.attachedDocuments).get(), isEmpty);
    expect(await db.select(db.documentChunks).get(), isEmpty);
  });

  test('the excerpts shrink to fit a small context window', () async {
    final modelId = await insertModel();
    final args = ChatRouteArgs(initialModelId: modelId);
    final c = build();
    final ctrl = await open(c, args);
    await ctrl.attachDocument();
    await ctrl.sendMessage('How long is the warranty?');
    int promptChars() => engine.lastMessages!
        .lastWhere((t) => t.role == EngineRole.user)
        .content
        .length;
    final roomy = promptChars();

    // Same document, tiny context window: fewer excerpt characters go in.
    await ctrl.setSamplingParams(
      const SamplingParams(contextLength: 1024, maxTokens: 256),
    );
    await ctrl.sendMessage('How long is the warranty again?');
    expect(promptChars(), lessThan(roomy));
  });
}
