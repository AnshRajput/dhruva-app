import 'dart:io';

import 'package:dhruva/core/di/engine_session.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/di/speed_providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/widgets/speed_label_chip.dart';
import 'package:dhruva/data/benchmark/speed_label.dart';
import 'package:dhruva/data/benchmark/speed_result.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/models_hub/state/speed_test_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledModelInfo _model(int id, String name) => InstalledModelInfo(
  id: id,
  repoId: 'r/$name',
  fileName: '$name.gguf',
  sizeBytes: 100,
  localPath: '/models/$name.gguf',
  gated: false,
  downloadedAt: DateTime.utc(2026, 11, 1),
);

FakeEngineService _engine({EngineFailure? loadFailure, int tokens = 20}) =>
    FakeEngineService(
      scriptedTokens: List.filled(tokens, 'x'),
      tokenDelay: const Duration(milliseconds: 1),
      loadFailure: loadFailure,
    );

void main() {
  late Directory dir;
  late SpeedResultStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('speed_ctrl_test');
    store = SpeedResultStore(File('${dir.path}/speed_results.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer make(FakeEngineService engine) {
    final c = ProviderContainer(
      overrides: [
        engineServiceProvider.overrideWithValue(engine),
        speedResultStoreProvider.overrideWith((ref) => store),
        appVersionProvider.overrideWithValue('9.9.9'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('runs, persists the result, unloads, and frees chat state', () async {
    final engine = _engine();
    final c = make(engine);
    c.read(loadedModelIdProvider.notifier).set(7);
    final a = _model(1, 'a');
    final b = _model(2, 'b');

    await c.read(speedTestControllerProvider.notifier).run([a, b]);

    final results = await c.read(speedResultsProvider.future);
    expect(results.keys, {
      speedKey(a.repoId, a.fileName),
      speedKey(b.repoId, b.fileName),
    });
    expect(results.values.first.appVersion, '9.9.9');
    expect((await store.load()).length, 2); // really on disk
    expect(engine.loadCount, 2);
    expect(engine.isLoaded, isFalse);
    expect(c.read(loadedModelIdProvider), isNull);
    expect(c.read(speedTestControllerProvider).active, isFalse);
    expect(c.read(engineLeaseProvider).speedTestRunning, isFalse);
  });

  test('refuses to start while chat is using the engine', () async {
    final engine = _engine();
    final c = make(engine);
    c.read(engineLeaseProvider).chatEnter();

    await c.read(speedTestControllerProvider.notifier).run([_model(1, 'a')]);

    expect(engine.loadCount, 0);
    expect(c.read(speedTestControllerProvider).notice, isNotNull);
    expect(c.read(speedTestControllerProvider).active, isFalse);
    expect(c.read(engineLeaseProvider).speedTestRunning, isFalse);
  });

  test('a speed test blocks a second start and chat busy-ness', () async {
    final lease = EngineLease();
    expect(lease.tryStartSpeedTest(), isTrue);
    expect(lease.tryStartSpeedTest(), isFalse);
    lease.endSpeedTest();
    lease.chatEnter();
    expect(lease.tryStartSpeedTest(), isFalse);
    lease.chatLeave();
    expect(lease.tryStartSpeedTest(), isTrue);
  });

  test('a failing model is reported and the engine is released', () async {
    final engine = _engine(loadFailure: const EngineLoadFailure('bad'));
    final c = make(engine);
    final a = _model(1, 'a');

    await c.read(speedTestControllerProvider.notifier).run([a]);

    final s = c.read(speedTestControllerProvider);
    expect(s.failures[speedKey(a.repoId, a.fileName)], isNotNull);
    expect((await c.read(speedResultsProvider.future)), isEmpty);
    expect(c.read(engineLeaseProvider).speedTestRunning, isFalse);
  });

  test('cancel stops the queue; nothing partial is saved', () async {
    final engine = _engine(tokens: 40);
    final c = make(engine);
    final ctrl = c.read(speedTestControllerProvider.notifier);

    final run = ctrl.run([_model(1, 'a'), _model(2, 'b')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ctrl.cancel();
    await run;

    expect(await c.read(speedResultsProvider.future), isEmpty);
    expect(engine.loadCount, 1); // second model never started
    expect(c.read(speedTestControllerProvider).active, isFalse);
  });

  test('offer is raised once per model and can be dismissed', () {
    final c = make(_engine());
    final offers = c.read(speedTestOfferProvider.notifier);
    offers.offer('k');
    offers.offer('k');
    expect(c.read(speedTestOfferProvider), ['k']);
    offers.dismiss('k');
    expect(c.read(speedTestOfferProvider), isEmpty);
    offers.offer('k'); // never re-offered
    expect(c.read(speedTestOfferProvider), isEmpty);
  });

  group('SpeedLabelChip', () {
    Future<void> pump(WidgetTester tester, SpeedResult? r) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: SpeedLabelChip(result: r)),
      ),
    );

    SpeedResult at(double tps) => SpeedResult(
      decodeTps: tps,
      prefillTps: 100,
      loadMs: 1,
      measuredAt: DateTime.utc(2026, 11, 1),
      appVersion: 'x',
    );

    testWidgets('shows plain-language copy for each band', (tester) async {
      await pump(tester, null);
      expect(find.text('Not tested'), findsOneWidget);
      await pump(tester, at(20));
      expect(find.text(SpeedLabel.fast.message), findsOneWidget);
      await pump(tester, at(8));
      expect(find.text('Usable'), findsOneWidget);
      await pump(tester, at(2));
      expect(
        find.text('Slow on your phone — try a smaller model'),
        findsOneWidget,
      );
    });
  });
}
