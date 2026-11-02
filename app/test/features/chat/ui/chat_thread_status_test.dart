// D1 markers + Continue, D3 warm-up / timeout / instant composer clear, as
// the user sees them in the thread.

import 'package:dhruva/core/actions/action_prompt.dart';
import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/intents/process_text.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:dhruva/features/chat/widgets/reply_status.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_health_fakes.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
          fileName: 'model.gguf',
          sizeBytes: 379 * 1024 * 1024,
          localPath: '/tmp/dhruva-status-test.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  /// A saved conversation: user turn, then an assistant reply with [status]
  /// and [content]. Returns the route args.
  Future<ChatRouteArgs> savedThread({
    required MessageStatus status,
    required String content,
    String? errorKind,
    bool secondTurn = false,
    String systemPrompt = '',
  }) async {
    final modelId = await insertModel();
    final r = ChatRepository(db: db);
    final convo = await r.createConversation(
      modelId: modelId,
      systemPrompt: systemPrompt,
    );
    await r.appendMessage(
      conversationId: convo,
      role: MessageRole.user,
      content: 'Tell me a story',
    );
    final reply = await r.appendMessage(
      conversationId: convo,
      role: MessageRole.assistant,
      content: content,
    );
    await r.finalize(reply, status: status, errorKind: errorKind);
    if (secondTurn) {
      await r.appendMessage(
        conversationId: convo,
        role: MessageRole.user,
        content: 'And then?',
      );
      final r2 = await r.appendMessage(
        conversationId: convo,
        role: MessageRole.assistant,
        content: 'The end.',
      );
      await r.finalize(r2, status: MessageStatus.complete);
    }
    return ChatRouteArgs(conversationId: convo);
  }

  Widget app(
    FakeEngineService engine,
    ChatRouteArgs args, {
    Duration? firstTokenTimeout,
    bool replaceable = false,
    ProcessTextBridge? bridge,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
        if (replaceable)
          processTextSessionProvider.overrideWith(_ReplaceableSession.new),
        if (bridge != null) processTextBridgeProvider.overrideWithValue(bridge),
        if (firstTokenTimeout != null)
          firstTokenTimeoutProvider.overrideWithValue(firstTokenTimeout),
        ...deviceHealthTestOverrides(),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ChatThreadScreen(args: args),
      ),
    );
  }

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('D1 markers', () {
    testWidgets('a cut-short reply says so and Continue resumes it', (
      tester,
    ) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.truncated,
        content: 'Once upon a time',
      );
      await tester.pumpWidget(
        app(
          FakeEngineService(
            scriptedTokens: const [' there ', 'was ', 'a ', 'fox.'],
          ),
          args,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cut short — reply was too long'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(
        find.textContaining('Once upon a time there was a fox.'),
        findsOneWidget,
      );
      expect(find.text('Cut short — reply was too long'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('a stopped reply is marked Stopped with Continue', (
      tester,
    ) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.cancelled,
        content: 'Once upon',
      );
      await tester.pumpWidget(app(FakeEngineService(), args));
      await tester.pumpAndSettle();

      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('Once upon'), findsOneWidget);
    });

    testWidgets('an errored reply keeps its text, names the error, and can '
        'continue', (tester) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.error,
        content: 'Half an answer',
        errorKind: 'EngineDecodeFailure',
      );
      await tester.pumpWidget(app(FakeEngineService(), args));
      await tester.pumpAndSettle();

      expect(find.textContaining('Half an answer'), findsOneWidget);
      expect(find.text('Stopped by an error'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('an errored reply with no text still shows the error card', (
      tester,
    ) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.error,
        content: '',
        errorKind: 'EngineDecodeFailure',
      );
      await tester.pumpWidget(app(FakeEngineService(), args));
      await tester.pumpAndSettle();

      expect(
        find.text('Something went wrong generating a response.'),
        findsOneWidget,
      );
      expect(find.text('Stopped by an error'), findsNothing);
    });

    testWidgets('a stopped reply with no text offers Try again, not Continue', (
      tester,
    ) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.cancelled,
        content: '',
      );
      await tester.pumpWidget(app(FakeEngineService(), args));
      await tester.pumpAndSettle();

      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('only the newest reply offers Continue', (tester) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.truncated,
        content: 'Once upon a time',
        secondTurn: true,
      );
      await tester.pumpWidget(app(FakeEngineService(), args));
      await tester.pumpAndSettle();

      // The older reply is still marked, but cannot be resumed.
      expect(find.text('Cut short — reply was too long'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });
  });

  group('D3 send, warm-up and timeout', () {
    testWidgets('the composer clears the instant send is tapped, before the '
        'reply starts', (tester) async {
      tall(tester);
      final modelId = await insertModel();
      await tester.pumpWidget(
        app(
          FakeEngineService(tokenDelay: const Duration(milliseconds: 500)),
          ChatRouteArgs(initialModelId: modelId),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      // ...while the reply is still pending.
      expect(find.byType(WarmUpStatus), findsOneWidget);
      // Let the slow reply finish so no timer outlives the test.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('no first token after the timeout shows plain copy with Stop '
        'and Try again; Stop ends it', (tester) async {
      tall(tester);
      final modelId = await insertModel();
      await tester.pumpWidget(
        app(
          FakeEngineService(tokenDelay: const Duration(seconds: 3)),
          ChatRouteArgs(initialModelId: modelId),
          firstTokenTimeout: const Duration(milliseconds: 300),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('This is taking longer than usual'), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('This is taking longer than usual'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      // The engine acknowledges the cancel on its next token boundary.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('This is taking longer than usual'), findsNothing);
      // The empty stopped reply is marked and can be retried.
      expect(find.text('Stopped'), findsOneWidget);
    });
  });

  group('D2 model load failures in the thread', () {
    Future<void> pumpFailing(WidgetTester tester, EngineFailure failure) async {
      tall(tester);
      final modelId = await insertModel();
      await tester.pumpWidget(
        app(
          FakeEngineService(loadFailure: failure),
          ChatRouteArgs(initialModelId: modelId),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('corrupt file: Try again, Use a smaller model, then '
        'Re-download with the real size', (tester) async {
      await pumpFailing(tester, const EngineLoadFailure('bad gguf'));

      expect(find.textContaining("file couldn't be read"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Use a smaller model'), findsOneWidget);
      expect(find.text('Re-download (379 MB)'), findsOneWidget);
      // Try again leaves the card up while it fails again, never a crash.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.textContaining("file couldn't be read"), findsOneWidget);
    });

    testWidgets('not enough memory: its own copy, no Re-download', (
      tester,
    ) async {
      await pumpFailing(tester, const EngineOutOfMemoryFailure('oom'));
      expect(find.textContaining('Not enough free memory'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Use a smaller model'), findsOneWidget);
      expect(find.textContaining('Re-download'), findsNothing);
    });

    testWidgets('timeout: says it took too long, no Re-download', (
      tester,
    ) async {
      await pumpFailing(tester, const EngineLoadTimeoutFailure('slow'));
      expect(find.textContaining('took too long to start'), findsOneWidget);
      expect(find.textContaining('Re-download'), findsNothing);
    });

    testWidgets('Use a smaller model with nothing smaller installed points '
        'at Discover', (tester) async {
      await pumpFailing(tester, const EngineLoadFailure('bad gguf'));
      await tester.tap(find.text('Use a smaller model'));
      await tester.pumpAndSettle();
      expect(find.text('You have no smaller model installed.'), findsOneWidget);
      expect(find.text('Find a smaller model'), findsOneWidget);
    });
  });

  group('Replace selected text (PROCESS_TEXT)', () {
    Future<ChatRouteArgs> doneThread() => savedThread(
      status: MessageStatus.complete,
      content: 'A tidier sentence.',
    );

    testWidgets('editable source: the newest reply offers the button and a '
        'tap hands the text back', (tester) async {
      tall(tester);
      final bridge = _FakeBridge();
      await tester.pumpWidget(
        app(
          FakeEngineService(),
          await doneThread(),
          replaceable: true,
          bridge: bridge,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Replace selected text'), findsOneWidget);
      await tester.tap(find.text('Replace selected text'));
      await tester.pump();
      expect(bridge.sent, ['A tidier sentence.']);
    });

    testWidgets('a refused hand-back explains and points at Copy', (
      tester,
    ) async {
      tall(tester);
      final bridge = _FakeBridge(failure: ProcessTextFailure.notReplaceable);
      await tester.pumpWidget(
        app(
          FakeEngineService(),
          await doneThread(),
          replaceable: true,
          bridge: bridge,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace selected text'));
      await tester.pump();
      expect(find.textContaining('Use Copy instead'), findsOneWidget);
    });

    testWidgets('read-only source (or a normal launch): no button', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(app(FakeEngineService(), await doneThread()));
      await tester.pumpAndSettle();
      expect(find.text('Replace selected text'), findsNothing);
    });

    testWidgets(
      'REGRESSION: an Action reply that is its own instruction (saved '
      'as complete before the guard) offers no Replace, only Try again',
      (tester) async {
        tall(tester);
        final args = await savedThread(
          status: MessageStatus.complete,
          content: "The user's next message is the text to work on.",
          systemPrompt: actionSystemPrompt(
            title: 'Fix grammar',
            instruction:
                'Fix the grammar and spelling of the text.\n'
                "The user's next message is the text to work on.",
          ),
        );
        final bridge = _FakeBridge();
        await tester.pumpWidget(
          app(FakeEngineService(), args, replaceable: true, bridge: bridge),
        );
        await tester.pumpAndSettle();

        expect(find.text('Replace selected text'), findsNothing);
        expect(find.textContaining('text to work on'), findsNothing);
        expect(
          find.textContaining('repeated its instructions'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(bridge.sent, isEmpty);
      },
    );

    for (final status in [
      MessageStatus.cancelled,
      MessageStatus.truncated,
      MessageStatus.error,
    ]) {
      testWidgets('a ${status.name} Action reply never offers replacing', (
        tester,
      ) async {
        tall(tester);
        final args = await savedThread(
          status: status,
          content: 'Half a fixed sentence',
          systemPrompt: actionSystemPrompt(
            title: 'Fix grammar',
            instruction: 'Fix the grammar and spelling of the text.',
          ),
        );
        await tester.pumpWidget(
          app(FakeEngineService(), args, replaceable: true),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Replace selected text'),
          findsNothing,
          reason: '$status',
        );
      });
    }

    testWidgets('an unfinished reply never offers replacing', (tester) async {
      tall(tester);
      final args = await savedThread(
        status: MessageStatus.truncated,
        content: 'Half a sentence',
      );
      await tester.pumpWidget(
        app(FakeEngineService(), args, replaceable: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Replace selected text'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('WarmUpStatus', () {
    final start = DateTime(2026, 11, 1, 9);

    Future<void> pump(
      WidgetTester tester, {
      required bool loading,
      required int elapsed,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: WarmUpStatus(
              modelName: 'Qwen 3B',
              loading: loading,
              since: start,
              now: () => start.add(Duration(seconds: elapsed)),
            ),
          ),
        ),
      );
    }

    testWidgets('loading: "Warming up <model> · 4 s"', (tester) async {
      await pump(tester, loading: true, elapsed: 4);
      expect(find.text('Warming up Qwen 3B · 4 s'), findsOneWidget);
    });

    testWidgets('loaded and quick: only the typing indicator', (tester) async {
      await pump(tester, loading: false, elapsed: 2);
      expect(find.textContaining('Warming up'), findsNothing);
      expect(find.textContaining('Thinking'), findsNothing);
    });

    testWidgets('loaded but slow: elapsed time appears', (tester) async {
      await pump(tester, loading: false, elapsed: 7);
      expect(find.text('Thinking · 7 s'), findsOneWidget);
    });
  });
}

class _ReplaceableSession extends ProcessTextSession {
  @override
  bool build() => true;
}

class _FakeBridge extends ProcessTextBridge {
  final ProcessTextFailure? failure;
  final sent = <String>[];
  _FakeBridge({this.failure});

  @override
  Future<ProcessTextFailure?> returnResult(String reply) async {
    sent.add(reply);
    return failure;
  }
}
