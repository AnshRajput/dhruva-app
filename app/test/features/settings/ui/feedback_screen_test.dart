// Feedback form: the crash-banner entry preselects Bug + crash log, and the
// post-handoff copy never claims the report was sent.

import 'dart:io';

import 'package:dhruva/core/crash/crash_banner.dart';
import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/feedback/feedback_report.dart';
import 'package:dhruva/core/feedback/feedback_sender.dart';
import 'package:dhruva/core/safety/report_mail.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/settings/state/feedback_controller.dart';
import 'package:dhruva/features/settings/state/feedback_inputs.dart';
import 'package:dhruva/features/settings/ui/feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Log extends CrashLog {
  _Log() : super(dir: () async => Directory.systemTemp);
  final records = [
    CrashRecord(
      timestamp: DateTime.utc(2026, 5, 1),
      appVersion: '0.7.0',
      appBuild: '106',
      platform: 'android',
      osVersion: '14',
      errorType: 'StateError',
      message: 'boom',
      stack: 's',
    ),
  ];
  @override
  Future<List<CrashRecord>> readAll() async => records;
  @override
  Future<List<CrashRecord>> unseen() async => records;
  @override
  Future<void> markSeen() async {}
}

class _Transport implements FeedbackTransport {
  _Transport({required this.email});
  final bool email;
  int composed = 0;

  @override
  Future<String> stageText(String fileName, String text) async =>
      '/tmp/$fileName';
  @override
  Future<void> composeEmail({
    required String to,
    required String subject,
    required String body,
    required List<String> attachmentPaths,
  }) async {
    if (!email) throw const EmailUnavailable();
    composed++;
  }

  @override
  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  }) async {}
}

const _info = FeedbackDeviceInfo(
  phoneModel: 'Pixel',
  os: 'Android 14',
  appVersion: '0.7.0',
  appBuild: '106',
);

Widget _app(FeedbackTransport transport, {String initial = '/'}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: CrashReportBanner()),
      ),
      GoRoute(
        path: '/settings/feedback',
        builder: (_, state) => FeedbackScreen(
          entry: feedbackEntryFromQuery(state.uri.queryParameters),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      crashLogProvider.overrideWithValue(_Log()),
      feedbackTransportProvider.overrideWithValue(transport),
      feedbackDeviceInfoProvider.overrideWith((_) async => _info),
    ],
    child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
}

void main() {
  testWidgets(
    'crash banner "Report this crash" opens Bug with crash log ticked',
    (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(_Transport(email: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('crash-report')));
      await tester.pumpAndSettle();

      final toggle = tester.widget<SegmentedButton<FeedbackType>>(
        find.byKey(const ValueKey('feedback-type')),
      );
      expect(toggle.selected, {FeedbackType.bug});
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('feedback-crash')),
            )
            .value,
        isTrue,
      );
      // Device info stays on by default; the steps field exists for Bug.
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('feedback-device')),
            )
            .value,
        isTrue,
      );
      expect(find.byKey(const ValueKey('feedback-steps')), findsOneWidget);
      expect(find.text(feedbackNeverIncluded), findsOneWidget);
    },
  );

  testWidgets(
    'Settings entry: crash log off by default; send hands off, never says sent',
    (tester) async {
      final transport = _Transport(email: true);
      _tall(tester);
      await tester.pumpWidget(
        _app(transport, initial: '/settings/feedback?type=feature'),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('feedback-crash')),
            )
            .value,
        isFalse,
      );
      expect(find.byKey(const ValueKey('feedback-steps')), findsNothing);

      // Empty form: plain-word errors, nothing composed.
      await tester.ensureVisible(find.byKey(const ValueKey('feedback-send')));
      await tester.tap(find.byKey(const ValueKey('feedback-send')));
      await tester.pumpAndSettle();
      expect(find.text('Add a short title.'), findsOneWidget);
      expect(transport.composed, 0);

      await tester.enterText(
        find.byKey(const ValueKey('feedback-title')),
        'Widget',
      );
      await tester.enterText(
        find.byKey(const ValueKey('feedback-description')),
        'A widget.',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('feedback-send')));
      await tester.tap(find.byKey(const ValueKey('feedback-send')));
      await tester.pumpAndSettle();

      expect(transport.composed, 1);
      expect(
        find.text('Thanks. Send it from your email app to reach us.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('feedback-copy-address')), findsNothing);
    },
  );

  testWidgets('no mail app: share-sheet fallback shows the address to copy', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(_Transport(email: false), initial: '/settings/feedback?type=bug'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('feedback-title')), 'T');
    await tester.enterText(
      find.byKey(const ValueKey('feedback-description')),
      'D',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('feedback-send')));
    await tester.tap(find.byKey(const ValueKey('feedback-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('feedback-copy-address')), findsOneWidget);
    expect(find.textContaining(developerEmail), findsOneWidget);
  });
}

/// The form is a lazy ListView: a tall screen builds every row.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
