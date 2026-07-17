import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget buildApp(FakeEngineService engine, ChatRouteArgs args) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(engine),
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
}
