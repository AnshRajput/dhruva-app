// Feedback form: the crash-banner entry preselects Bug + crash log, both
// hand-off paths are always offered (a signed-out Gmail "succeeds" without
// composing, so the share sheet must never hide behind a failure), the
// confirmation is in place before the mail app launches, and it never claims
// the report was sent.

import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/crash/crash_banner.dart';
import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/feedback/feedback_draft_store.dart';
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

  final recorded = <Object>[];
  @override
  Future<void> record(Object error, StackTrace? stack) async =>
      recorded.add(error);
}

class _FailingTransport extends _Transport {
  @override
  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  }) async => throw ArgumentError('files provided, but cannot be empty');
}

class _Transport implements FeedbackTransport {
  _Transport({this.email = true, this.hold});
  final bool email;

  /// When set, composeEmail waits on it: the mail app "has the screen".
  final Completer<void>? hold;
  int composed = 0;
  final shared = <Map<String, Object?>>[];

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
    await hold?.future;
  }

  @override
  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  }) async {
    shared.add({'text': text, 'files': filePaths});
  }
}

class _Store implements FeedbackDraftStore {
  SavedFeedbackDraft? saved;
  @override
  Future<SavedFeedbackDraft?> load() async => saved;
  @override
  Future<void> save(SavedFeedbackDraft draft) async => saved = draft;
  @override
  Future<void> clear() async => saved = null;
}

class _Picker implements FeedbackMediaPicker {
  @override
  Future<List<FeedbackAttachment>> pick(int limit) async => const [
    FeedbackAttachment(path: '/cache/shot.png', name: 'shot.png', bytes: 2048),
  ];
}

const _info = FeedbackDeviceInfo(
  phoneModel: 'Pixel',
  os: 'Android 14',
  appVersion: '0.7.0',
  appBuild: '106',
);

Widget _app(
  FeedbackTransport transport, {
  String initial = '/',
  _Store? store,
  _Log? log,
}) {
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
      crashLogProvider.overrideWithValue(log ?? _Log()),
      feedbackTransportProvider.overrideWithValue(transport),
      feedbackDeviceInfoProvider.overrideWith((_) async => _info),
      feedbackDraftStoreProvider.overrideWithValue(store ?? _Store()),
      feedbackMediaPickerProvider.overrideWithValue(_Picker()),
    ],
    child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('feedback-title')), 'T');
  await tester.enterText(
    find.byKey(const ValueKey('feedback-description')),
    'D',
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'crash banner "Report this crash" opens Bug with crash log ticked',
    (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(_Transport()));
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
    'Settings entry: crash log off by default; email hand-off never says sent',
    (tester) async {
      final transport = _Transport();
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
      await _tap(tester, 'feedback-send');
      expect(find.text('Add a short title.'), findsOneWidget);
      expect(transport.composed, 0);

      await _fill(tester);
      await _tap(tester, 'feedback-send');

      expect(transport.composed, 1);
      expect(
        find.text('Thanks. Send it from your email app to reach us.'),
        findsOneWidget,
      );
      expect(find.textContaining('was sent'), findsNothing);
    },
  );

  testWidgets('the share sheet and copy address are always available', (
    tester,
  ) async {
    final transport = _Transport();
    _tall(tester);
    await tester.pumpWidget(_app(transport, initial: '/settings/feedback'));
    await tester.pumpAndSettle();

    // Before anything is tapped: both options and the copy action exist.
    expect(find.byKey(const ValueKey('feedback-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback-copy-address')), findsOneWidget);

    await _fill(tester);
    await _tap(tester, 'feedback-share');

    expect(transport.composed, 0);
    expect(transport.shared, hasLength(1));
    expect(
      transport.shared.single['text'] as String,
      startsWith('Please send to $developerEmail\n\nType: Bug'),
    );
  });

  testWidgets('the confirmation offers "Share another way" to recover', (
    tester,
  ) async {
    final transport = _Transport();
    _tall(tester);
    await tester.pumpWidget(_app(transport, initial: '/settings/feedback'));
    await tester.pumpAndSettle();
    await _fill(tester);
    await _tap(tester, 'feedback-send');

    expect(transport.shared, isEmpty);
    expect(find.textContaining("Didn't open a draft?"), findsOneWidget);
    await _tap(tester, 'feedback-share-recovery');
    expect(transport.shared, hasLength(1));
    expect(transport.shared.single['text'] as String, contains('Title: T'));
  });

  testWidgets('no mail app: falls back to the share sheet automatically', (
    tester,
  ) async {
    final transport = _Transport(email: false);
    _tall(tester);
    await tester.pumpWidget(
      _app(transport, initial: '/settings/feedback?type=bug'),
    );
    await tester.pumpAndSettle();
    await _fill(tester);
    await _tap(tester, 'feedback-send');

    expect(transport.shared, hasLength(1));
    expect(find.textContaining(developerEmail), findsWidgets);
  });

  testWidgets(
    'the confirmation is on screen before the mail app returns (set BEFORE '
    'launch) and the draft is already saved',
    (tester) async {
      final hold = Completer<void>();
      final store = _Store();
      _tall(tester);
      await tester.pumpWidget(
        _app(
          _Transport(hold: hold),
          initial: '/settings/feedback',
          store: store,
        ),
      );
      await tester.pumpAndSettle();
      await _fill(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('feedback-send')));
      await tester.tap(find.byKey(const ValueKey('feedback-send')));
      await tester.pump(const Duration(milliseconds: 50));

      // The composer call has not returned yet.
      expect(hold.isCompleted, isFalse);
      expect(find.byKey(const ValueKey('feedback-handoff')), findsOneWidget);
      expect(store.saved?.title, 'T');

      hold.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a failed hand-off shows the error and is logged, not swallowed',
    (tester) async {
      final log = _Log();
      _tall(tester);
      await tester.pumpWidget(
        _app(_FailingTransport(), initial: '/settings/feedback', log: log),
      );
      await tester.pumpAndSettle();
      await _fill(tester);
      await _tap(tester, 'feedback-share');

      expect(
        find.text(
          "Couldn't open your email app or the share sheet. Try again.",
        ),
        findsOneWidget,
      );
      expect(log.recorded.single, isA<ArgumentError>());
      expect(find.byKey(const ValueKey('feedback-handoff')), findsNothing);
    },
  );

  testWidgets('a saved draft is restored, and Done clears it', (tester) async {
    final store = _Store()
      ..saved = const SavedFeedbackDraft(
        type: FeedbackType.bug,
        title: 'Saved title',
        description: 'Saved body',
      );
    _tall(tester);
    await tester.pumpWidget(
      _app(_Transport(), initial: '/settings/feedback?type=bug', store: store),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved title'), findsOneWidget);
    expect(find.text('Saved body'), findsOneWidget);

    await _tap(tester, 'feedback-send');
    await _tap(tester, 'feedback-done');
    expect(store.saved, isNull);
  });

  testWidgets(
    'attachment row: immediate placeholder, 48 dp remove, "Remove attachment"',
    (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _app(_Transport(), initial: '/settings/feedback'),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'feedback-add-media');

      expect(find.text('shot.png'), findsOneWidget);
      // Missing file: the placeholder icon is what shows, never nothing.
      expect(find.byIcon(Icons.image_outlined), findsWidgets);
      final remove = find.byKey(const ValueKey('feedback-remove'));
      expect(tester.getSize(remove), const Size(48, 48));
      expect(find.byTooltip('Remove attachment'), findsOneWidget);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('shot.png'), findsNothing);
    },
  );
}

/// The form is a lazy ListView: a tall screen builds every row.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
