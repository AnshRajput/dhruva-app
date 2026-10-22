import 'dart:io';

import 'package:dhruva/core/crash/crash_banner.dart';
import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/settings/ui/crash_reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory log: widget tests can't await real file IO.
class FakeLog extends CrashLog {
  FakeLog(this.records) : super(dir: () async => Directory.systemTemp);
  List<CrashRecord> records;
  bool seen = false;

  @override
  Future<List<CrashRecord>> readAll() async => records;
  @override
  Future<List<CrashRecord>> unseen() async => seen ? [] : records;
  @override
  Future<void> markSeen() async => seen = true;
  @override
  Future<void> clear() async => records = [];
}

CrashRecord rec(String msg) => CrashRecord(
  timestamp: DateTime.utc(2026, 5, 1, 10, 30),
  appVersion: '0.6.0',
  appBuild: '103',
  platform: 'android',
  osVersion: '14',
  errorType: 'StateError',
  message: msg,
  stack: 'stack here',
);

Widget host(FakeLog log, Widget child) => ProviderScope(
  overrides: [crashLogProvider.overrideWithValue(log)],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('banner hidden with no reports', (tester) async {
    await tester.pumpWidget(host(FakeLog([]), const CrashReportBanner()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crash-banner')), findsNothing);
  });

  testWidgets('banner shows for new reports and dismiss hides it', (
    tester,
  ) async {
    final log = FakeLog([rec('boom')]);
    await tester.pumpWidget(host(log, const CrashReportBanner()));
    await tester.pumpAndSettle();
    expect(
      find.text('Dhruva hit a problem last time. Send a crash report?'),
      findsOneWidget,
    );
    expect(find.text('Send'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crash-dismiss')));
    await tester.pumpAndSettle();
    expect(log.seen, isTrue);
    expect(find.byKey(const ValueKey('crash-banner')), findsNothing);
  });

  testWidgets('settings screen lists reports, views, deletes all', (
    tester,
  ) async {
    final log = FakeLog([rec('first line\nsecond line')]);
    await tester.pumpWidget(host(log, const CrashReportsScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing is sent unless'), findsOneWidget);
    expect(find.text('StateError'), findsOneWidget);
    expect(find.textContaining('first line'), findsOneWidget);
    expect(find.textContaining('second line'), findsNothing);

    await tester.tap(find.text('StateError'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stack here'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('crash-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('crash-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('No crash reports.'), findsOneWidget);
  });
}
