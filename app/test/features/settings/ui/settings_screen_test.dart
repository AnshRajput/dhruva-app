// Settings screen (Amendment 4b/2b): storage summary renders, the double
// confirmation on Clear all history actually deletes conversations through
// the real repository/db, and the credit row launches the portfolio URL
// through url_launcher's platform interface.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/settings/ui/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late AppDatabase db;
  late ChatRepository repo;
  late _FakeUrlLauncher fakeLauncher;
  final realLauncher = UrlLauncherPlatform.instance;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChatRepository(db: db);
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() async {
    await db.close();
    UrlLauncherPlatform.instance = realLauncher;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('storage summary renders installed count and size', (
    tester,
  ) async {
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'x.gguf',
            sizeBytes: 800 * 1024 * 1024,
            localPath: '/models/x.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    await pump(tester);

    expect(find.text('1 model · 800 MB used'), findsOneWidget);
  });

  testWidgets('clear all history requires two confirmations, then deletes every '
      'conversation without touching installed models', (tester) async {
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
    await repo.createConversation(title: 'Old chat', modelId: modelId);

    await pump(tester);

    await tester.tap(find.text('Clear all chat history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all chat history?'), findsOneWidget);

    // First confirmation only advances to the second dialog — nothing is
    // deleted yet.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Are you sure?'), findsOneWidget);
    expect(await repo.listConversations(), hasLength(1));

    await tester.tap(find.text('Clear all history'));
    await tester.pumpAndSettle();

    expect(await repo.listConversations(), isEmpty);
    expect(await db.select(db.installedModels).get(), hasLength(1));
    // UX-hardening A2: the apologetic "pull to refresh" instruction is gone
    // — the Chat list now refreshes itself via conversationListRevisionProvider.
    expect(find.text('Chat history cleared.'), findsOneWidget);
  });

  testWidgets('cancelling the first dialog deletes nothing', (tester) async {
    await repo.createConversation(title: 'Keep me');
    await pump(tester);

    await tester.tap(find.text('Clear all chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await repo.listConversations(), hasLength(1));
  });

  testWidgets('credit row launches the portfolio URL', (tester) async {
    await pump(tester);

    await tester.tap(find.textContaining('Ansh Singh Rajput'));
    await tester.pumpAndSettle();

    expect(fakeLauncher.launched, contains('https://anshgandharva.online'));
  });

  testWidgets(
    'About row links to the dedicated About page, showing the version '
    'inline as a preview',
    (tester) async {
      await pump(tester);

      expect(find.text('About Dhruva AI'), findsOneWidget);
      expect(find.text('Version 0.3.1'), findsOneWidget);
    },
  );
}
