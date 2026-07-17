import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:dhruva/vision/fake_image_attacher.dart';
import 'package:dhruva/vision/image_attach_source.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _redPng = File('test/assets/red_64.png').readAsBytesSync();

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertModel() {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-thread-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  }

  // Loop 7: a vision-capable installed row (mmprojPath set).
  Future<int> insertVisionModel() {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
            fileName: 'vision-model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-thread-vision-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
            mmprojPath: const Value('/tmp/dhruva-thread-mmproj.gguf'),
            isVision: const Value(true),
          ),
        );
  }

  Widget buildApp(
    FakeEngineService engine,
    ChatRouteArgs args, {
    FakeImageAttacher? imageAttacher,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        if (imageAttacher != null)
          imageAttacherProvider.overrideWithValue(imageAttacher),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ChatThreadScreen(args: args),
      ),
    );
  }

  testWidgets(
    'a new draft thread shows the trust mark and composer, no model chip error',
    (tester) async {
      final modelId = await insertModel();
      await tester.pumpWidget(
        buildApp(FakeEngineService(), ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Runs 100% on your device'), findsOneWidget);
      expect(find.text('Llama-3.2-1B-Instruct'), findsOneWidget);
      expect(find.text('Message Dhruva…'), findsOneWidget);
    },
  );

  testWidgets('with no model installed, the chip reads "Pick a model"', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(FakeEngineService(), const ChatRouteArgs()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick a model'), findsOneWidget);
    expect(find.text('No model installed yet'), findsOneWidget);
    // Designer BLOCKING #1 / chat-spec.md §7.1: no composer visible on
    // this state — a disabled composer under an empty state is worse than
    // omitting it.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('DESIGNER BLOCKING #1: an existing conversation whose model was '
      'uninstalled (Conversations.modelId FKs setNull on delete) hides the '
      'composer too, not just a brand-new draft — the message history stays '
      'visible, the AppBar chip still offers "Pick a model"', (tester) async {
    final modelId = await insertModel();
    final repo = ChatRepository(db: db);
    final conversationId = await repo.createConversation(modelId: modelId);
    await repo.appendMessage(
      conversationId: conversationId,
      role: MessageRole.user,
      content: 'hello from before the model was deleted',
    );
    await (db.delete(
      db.installedModels,
    )..where((t) => t.id.equals(modelId))).go();

    await tester.pumpWidget(
      buildApp(
        FakeEngineService(),
        ChatRouteArgs(conversationId: conversationId),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick a model'), findsOneWidget);
    expect(
      find.text('hello from before the model was deleted'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'sending a message streams tokens and renders the assistant reply',
    (tester) async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: const ['Bon', 'jour', '!'],
        tokenDelay: const Duration(milliseconds: 10),
      );
      await tester.pumpWidget(
        buildApp(engine, ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(
        const Duration(milliseconds: 5),
      ); // user bubble + isGenerating flip
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.textContaining('Bonjour!'), findsOneWidget);
      expect(
        find.byIcon(Icons.arrow_upward_rounded),
        findsOneWidget,
      ); // back to send state
    },
  );

  testWidgets(
    'cancel mid-generation renders a cancelled turn without crashing',
    (tester) async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        scriptedTokens: List.generate(30, (i) => 'w$i '),
        tokenDelay: const Duration(milliseconds: 20),
      );
      await tester.pumpWidget(
        buildApp(engine, ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'go');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      // Advance well into the 30-token/20ms-each stream (~600ms total) so the
      // stop button is reliably showing, without racing a single frame.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'a generation error renders an inline error card with a retry action',
    (tester) async {
      final modelId = await insertModel();
      final engine = FakeEngineService(
        generateFailure: const EngineDecodeFailure('boom'),
      );
      await tester.pumpWidget(
        buildApp(engine, ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(
        find.text('Something went wrong generating a response.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'FIXED (QA BUG-1): a 0-token assistant response renders an honest '
    '"No response — try regenerating." placeholder once the stream '
    'finishes, instead of an empty "ghost bubble" — the metadata row (and '
    'its regenerate affordance) still renders alongside it',
    (tester) async {
      final modelId = await insertModel();
      final engine = FakeEngineService(scriptedTokens: const []);
      await tester.pumpWidget(
        buildApp(engine, ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Generation is over (back to the send icon)...
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      // ...and the finalized empty assistant turn is honest about it
      // instead of showing a blank bubble.
      expect(find.text('No response — try regenerating.'), findsOneWidget);
      // The metadata row (relative-time label) still renders, same as any
      // other assistant turn.
      expect(find.text('now'), findsOneWidget);
    },
  );

  testWidgets(
    'Loop 5: a character-bound conversation shows the character\'s avatar '
    'and name in the AppBar, alongside the model chip',
    (tester) async {
      final modelId = await insertModel();
      final now = DateTime.now();
      final characterId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Coach',
              avatarEmoji: const Value('💪'),
              personaSystemPrompt: 'Be an encouraging coach.',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final repo = ChatRepository(db: db);
      final conversationId = await repo.createConversation(
        modelId: modelId,
        characterId: characterId,
        systemPrompt: 'Be an encouraging coach.',
      );

      await tester.pumpWidget(
        buildApp(
          FakeEngineService(),
          ChatRouteArgs(conversationId: conversationId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('💪'), findsOneWidget);
      // The model chip is still there too (alongside, not instead of).
      expect(find.text('Llama-3.2-1B-Instruct'), findsOneWidget);
    },
  );

  testWidgets(
    'attack list #6: a character with no default model (and no fallback '
    'installed model on this device) still surfaces "Pick a model" — the '
    'character binding does not strand the conversation with an '
    'unreachable model picker',
    (tester) async {
      // An installed model exists on-device (so the picker itself has
      // something to offer once opened) but the character has no
      // defaultModelId and the draft has no fallback initialModelId.
      await insertModel();
      final now = DateTime.now();
      final characterId = await db
          .into(db.characters)
          .insert(
            CharactersCompanion.insert(
              name: 'Coach',
              avatarEmoji: const Value('💪'),
              personaSystemPrompt: 'Be an encouraging coach.',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await tester.pumpWidget(
        buildApp(FakeEngineService(), ChatRouteArgs(characterId: characterId)),
      );
      await tester.pumpAndSettle();

      // Character identity still shows even with no model resolved.
      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('💪'), findsOneWidget);
      expect(find.text('Pick a model'), findsOneWidget);

      await tester.tap(find.text('Pick a model'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a model'), findsOneWidget);
      expect(find.text('Llama-3.2-1B-Instruct'), findsOneWidget);
    },
  );

  group('Loop 7: vision', () {
    testWidgets('gate G3: a text-only loaded model hides the attach button', (
      tester,
    ) async {
      final modelId = await insertModel();
      await tester.pumpWidget(
        buildApp(FakeEngineService(), ChatRouteArgs(initialModelId: modelId)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
    });

    testWidgets(
      'gate G3: a vision-capable loaded model shows the attach button',
      (tester) async {
        final modelId = await insertVisionModel();
        await tester.pumpWidget(
          buildApp(
            FakeEngineService(multimodal: true),
            ChatRouteArgs(initialModelId: modelId),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'D2: attaching + sending an image renders it in the user bubble and '
      "the model's grounded vision answer streams in",
      (tester) async {
        final modelId = await insertVisionModel();
        final engine = FakeEngineService(
          multimodal: true,
          visionTokens: const ['a ', 'red ', 'square', '.'],
          tokenDelay: const Duration(milliseconds: 5),
        );
        final imageAttacher = FakeImageAttacher()..nextImage = _redPng;
        await tester.pumpWidget(
          buildApp(
            engine,
            ChatRouteArgs(initialModelId: modelId),
            imageAttacher: imageAttacher,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Photo Library'));
        await tester.pumpAndSettle();
        expect(imageAttacher.lastSource, ImageAttachSource.gallery);

        await tester.enterText(find.byType(TextField), 'what is this?');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));

        // The image renders in the user's bubble (thumbnail).
        expect(find.byType(Image), findsWidgets);
        // The vision-canned answer streamed in as the assistant reply.
        expect(find.textContaining('a red square.'), findsOneWidget);
      },
    );

    testWidgets('D3: extract-text preset answer shows a copy affordance', (
      tester,
    ) async {
      final modelId = await insertVisionModel();
      final engine = FakeEngineService(
        multimodal: true,
        visionTokens: const ['EXTRACTED TEXT'],
        tokenDelay: const Duration(milliseconds: 5),
      );
      final imageAttacher = FakeImageAttacher()..nextImage = _redPng;
      await tester.pumpWidget(
        buildApp(
          engine,
          ChatRouteArgs(initialModelId: modelId),
          imageAttacher: imageAttacher,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo Library'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Extract text'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('EXTRACTED TEXT'), findsOneWidget);
      expect(find.byTooltip('Copy text'), findsOneWidget);
    });
  });
}
