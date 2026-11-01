import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {required bool openVoice}) async {
    final modelId = await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-talk-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ChatThreadScreen(
            args: ChatRouteArgs(initialModelId: modelId),
            openVoiceOnStart: openVoice,
          ),
        ),
        GoRoute(
          path: '/voice/handsfree',
          builder: (_, _) => const Scaffold(body: Text('hands-free stub')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(FakeEngineService()),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('openVoiceOnStart opens hands-free once the chat is ready', (
    tester,
  ) async {
    await pump(tester, openVoice: true);
    expect(find.text('hands-free stub'), findsOneWidget);
  });

  testWidgets('without openVoiceOnStart the chat stays put', (tester) async {
    await pump(tester, openVoice: false);
    expect(find.text('hands-free stub'), findsNothing);
  });
}
