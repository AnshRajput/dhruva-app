// On-device golden path for v0.6.0: import a local GGUF through the real
// StorageController → open a Workflow with shared text → Run → a real model
// reply is generated and persisted. Exercises the whole stack (import copy,
// DB registration, router, workflow rendering, engine load + generation).
//
// Setup: adb push SmolLM2-135M-Instruct-Q4_K_M.gguf /data/local/tmp/
// Run:   flutter test integration_test/golden_path_workflow_test.dart -d <id>
import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/models_hub/state/storage_controller.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:dhruva/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _modelPath = '/data/local/tmp/SmolLM2-135M-Instruct-Q4_K_M.gguf';
const _shared =
    'The meeting moved to Thursday at 3pm. Priya will send the budget '
    'draft by Wednesday, and Arjun needs to book the conference room.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'import GGUF → Summarize workflow → real reply',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await (await container.read(
        onboardingStoreProvider.future,
      )).markComplete();
      await container.read(storageControllerProvider.future);
      await container
          .read(storageControllerProvider.notifier)
          .importLocal(File(_modelPath));
      final storage = await container.read(storageControllerProvider.future);
      expect(
        storage.installed.map((m) => m.repoId),
        contains('local/SmolLM2-135M-Instruct-Q4_K_M'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const DhruvaApp(),
        ),
      );
      appRouter.go('/workflows?text=${Uri.encodeComponent(_shared)}');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Summarize').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run'));

      // Poll the DB (not the widget tree) for a completed assistant reply.
      final db = container.read(appDatabaseProvider);
      Message? reply;
      for (var i = 0; i < 180 && reply == null; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        final rows = await (db.select(
          db.messages,
        )..where((m) => m.role.equalsValue(MessageRole.assistant))).get();
        reply = rows
            .where((m) => m.status == MessageStatus.complete)
            .where((m) => m.content.trim().isNotEmpty)
            .firstOrNull;
      }
      // ignore: avoid_print
      print('DHRUVA WORKFLOW PROOF: "${reply?.content}"');
      expect(reply, isNotNull, reason: 'no completed assistant reply in 90s');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
