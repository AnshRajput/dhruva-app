import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/safety/report_mail.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/chat/state/message_info_x.dart';
import 'package:dhruva/features/chat/widgets/message_bubble.dart';
import 'package:dhruva/features/chat/widgets/report_sheet.dart';
import 'package:dhruva/features/settings/ui/safety_screen.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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
  late int convoId;
  late int msgId;
  late _FakeUrlLauncher launcher;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final chat = ChatRepository(db: db);
    convoId = await chat.createConversation();
    msgId = await chat.appendMessage(
      conversationId: convoId,
      role: MessageRole.assistant,
      content: 'something awful',
    );
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => db.close());

  MessageInfo message({bool reported = false}) => MessageInfo(
    id: msgId,
    conversationId: convoId,
    role: MessageRole.assistant,
    content: 'something awful',
    status: MessageStatus.complete,
    createdAt: DateTime.now(),
    reported: reported,
  );

  Widget harness() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      audioSinkProvider.overrideWithValue(FakeAudioSink()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            var current = message();
            return StatefulBuilder(
              builder: (context, setInner) => MessageBubble(
                message: current,
                onReport: () => showReportSheet(
                  context,
                  message: current,
                  modelName: 'tiny.gguf',
                  onReported: () => setInner(
                    () => current = current.copyWith(reported: true),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  testWidgets('flag opens the sheet; Report saves and hides the reply', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    expect(find.text('something awful'), findsOneWidget);

    await tester.tap(find.byTooltip('Report this reply'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reports stay on your phone unless you choose to email them.'),
      findsOneWidget,
    );
    // Nothing can be sent before a reason is chosen.
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Report'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Sexual content'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'please remove');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Report'));
    await tester.pumpAndSettle();

    final saved = await ReportRepoAccess(db).all();
    expect(saved, hasLength(1));
    expect(saved.single.reason, 'sexual');
    expect(saved.single.note, 'please remove');
    expect(saved.single.modelName, 'tiny.gguf');
    expect(launcher.launched, isEmpty);

    expect(find.text('something awful'), findsNothing);
    expect(find.text("You reported this reply. It's hidden."), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('something awful'), findsOneWidget);
  });

  testWidgets('Report & email developer also opens a prefilled mailto', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byTooltip('Report this reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Harmful or dangerous'));
    await tester.pump();
    await tester.tap(find.text('Report & email developer'));
    await tester.pumpAndSettle();

    expect((await ReportRepoAccess(db).all()), hasLength(1));
    expect(launcher.launched, hasLength(1));
    final uri = Uri.parse(launcher.launched.single);
    expect(uri.scheme, 'mailto');
    expect(uri.path, developerEmail);
    expect(uri.queryParameters['subject'], 'Dhruva AI content report');
    final body = uri.queryParameters['body']!;
    expect(body, contains('Reason: Harmful or dangerous'));
    expect(body, contains('Model: tiny.gguf'));
    expect(body, contains('App version:'));
    expect(body, contains('something awful'));
  });

  testWidgets('an already-reported message renders collapsed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioSinkProvider.overrideWithValue(FakeAudioSink())],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: MessageBubble(message: message(reported: true))),
        ),
      ),
    );
    expect(find.text("You reported this reply. It's hidden."), findsOneWidget);
    expect(find.text('something awful'), findsNothing);
  });

  testWidgets('Safety screen lists reports and deletes them', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.dark, home: const SafetyScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No reports yet.'), findsOneWidget);
    expect(
      find.text("We use reports to improve Dhruva's default safety rules."),
      findsOneWidget,
    );

    await tester.runAsync(
      () => ReportRepoAccess(db).add(convoId, msgId, 'something awful'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Hate or harassment'), findsOneWidget);
    expect(find.text('something awful'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete report'));
    await tester.pumpAndSettle();
    expect(find.text('No reports yet.'), findsOneWidget);

    await tester.tap(find.text('Contact developer'));
    await tester.pump();
    expect(launcher.launched.single, startsWith('mailto:$developerEmail'));

    // Unmount, then let drift's zero-duration "stream closed" timer fire.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

/// Thin test-side access to the saved rows (the repository is exercised in
/// `report_repository_test.dart`; this keeps the widget tests on raw rows).
class ReportRepoAccess {
  final AppDatabase db;
  ReportRepoAccess(this.db);

  Future<List<ContentReport>> all() => db.select(db.contentReports).get();

  Future<void> add(int convoId, int msgId, String excerpt) => db
      .into(db.contentReports)
      .insert(
        ContentReportsCompanion.insert(
          createdAt: DateTime.now(),
          conversationId: convoId,
          messageId: msgId,
          reason: 'hate',
          excerpt: excerpt,
        ),
      );
}
