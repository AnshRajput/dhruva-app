// Drives the real app on a simulator into store-screenshot states. Prints
// `SHOT <name>` and holds the screen; scripts/capture-store-shots.sh watches
// the log and grabs each frame with `xcrun simctl io <udid> screenshot`.
//
// Needs a real GGUF reachable from the simulator process:
//   --dart-define=SHOT_MODEL=/abs/path/model.gguf
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

const _model = String.fromEnvironment('SHOT_MODEL');

const _bill =
    'Electricity bill, October. Units consumed: 412 kWh (last month 298). '
    'Fixed charge Rs 150, energy charge Rs 3,296, fuel surcharge Rs 214, '
    'late payment fee Rs 100 from previous cycle. Total payable Rs 3,760. '
    'Due date 28 October. Disconnection notice applies after 15 days unpaid.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    expect(_model, isNotEmpty, reason: 'pass --dart-define=SHOT_MODEL=...');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await (await container.read(onboardingStoreProvider.future)).markComplete();
    await container.read(storageControllerProvider.future);
    await container
        .read(storageControllerProvider.notifier)
        .importLocal(File(_model));

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DhruvaApp()),
    );
    final db = container.read(appDatabaseProvider);

    Future<void> shot(String name) async {
      await tester.pump(const Duration(seconds: 2));
      // ignore: avoid_print
      print('SHOT $name');
      await tester.pump(const Duration(seconds: 6));
    }

    // Waits until a new assistant reply exists and its text stops changing.
    Future<void> awaitReply(int before) async {
      var last = '';
      var stable = 0;
      for (var i = 0; i < 600 && stable < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        final rows = await (db.select(
          db.messages,
        )..where((m) => m.role.equalsValue(MessageRole.assistant))).get();
        if (rows.length <= before) continue;
        final text = rows.last.content;
        stable = text.isNotEmpty && text == last ? stable + 1 : 0;
        last = text;
      }
    }

    Future<int> replies() async => (await (db.select(
      db.messages,
    )..where((m) => m.role.equalsValue(MessageRole.assistant))).get()).length;

    // 1. A workflow on a private document.
    appRouter.go('/workflows?text=${Uri.encodeComponent(_bill)}');
    await tester.pumpAndSettle();
    await shot('02_workflows');
    await tester.tap(find.text('Understand a document').first);
    await tester.pumpAndSettle();
    var n = await replies();
    await tester.tap(find.text('Run'));
    await awaitReply(n);
    await shot('03_workflow_reply');

    // 2. A plain chat.
    n = await replies();
    appRouter.go(
      '/chat/new?prompt=${Uri.encodeComponent('Give me 3 quick, healthy dinner ideas with paneer.')}',
    );
    await awaitReply(n);
    await shot('04_chat');

    // 3. Home, models, characters.
    appRouter.go('/chat');
    await tester.pumpAndSettle();
    await shot('01_home');
    appRouter.go('/models');
    await tester.pumpAndSettle();
    await shot('05_models');
    appRouter.go('/characters');
    await tester.pumpAndSettle();
    await shot('06_characters');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
