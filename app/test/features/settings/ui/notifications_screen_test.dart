// Settings > Notifications: the morning brief switch, wired to a real
// scheduler over a fake OS gateway.

import 'package:dhruva/core/intents/app_settings.dart';
import 'package:dhruva/core/notifications/morning_brief.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/settings/ui/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_notification_gateway.dart';

Future<void> _pump(
  WidgetTester tester,
  FakeGateway gateway,
  MemoryPrefsStore prefs, {
  void Function()? onOpenSettings,
}) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWith((ref) async => prefs),
        notificationGatewayProvider.overrideWithValue(gateway),
        openAppSettingsProvider.overrideWithValue(() async {
          onOpenSettings?.call();
          return true;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const NotificationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _switch(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(SwitchListTile),
);

void main() {
  testWidgets('morning brief is off by default and the switch is real', (
    tester,
  ) async {
    await _pump(tester, FakeGateway(), MemoryPrefsStore());
    expect(find.byKey(const ValueKey('morning-brief-coming')), findsNothing);
    expect(
      tester.widget<SwitchListTile>(_switch('morning-brief-switch')).value,
      isFalse,
    );
    expect(find.byKey(const ValueKey('morning-brief-time')), findsNothing);
    // The promise is on screen: generic text only.
    expect(find.textContaining('Your brief is ready to read'), findsOneWidget);
  });

  testWidgets('turning it on asks for permission, schedules, and persists', (
    tester,
  ) async {
    final gateway = FakeGateway();
    final prefs = MemoryPrefsStore();
    await _pump(tester, gateway, prefs);
    await tester.tap(find.byKey(const ValueKey('morning-brief-switch')));
    await tester.pumpAndSettle();
    expect(gateway.permissionRequests, 1);
    expect(gateway.scheduled.length, scheduleDays);
    expect(prefs.values['morning_brief_enabled'], 'true');
    expect(find.byKey(const ValueKey('morning-brief-time')), findsOneWidget);
    expect(find.text('7:30 AM'), findsOneWidget); // the 07:30 default
  });

  testWidgets('permission refused: stays off, says how to fix, Open settings '
      'works', (tester) async {
    final gateway = FakeGateway(permitted: false);
    final prefs = MemoryPrefsStore();
    var opened = 0;
    await _pump(tester, gateway, prefs, onOpenSettings: () => opened++);
    await tester.tap(find.byKey(const ValueKey('morning-brief-switch')));
    await tester.pumpAndSettle();
    expect(gateway.scheduled, isEmpty);
    expect(prefs.values['morning_brief_enabled'], isNull);
    expect(
      tester.widget<SwitchListTile>(_switch('morning-brief-switch')).value,
      isFalse,
    );
    expect(find.text('Notifications are off for this app'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('morning-brief-open-settings')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('turning it off cancels the scheduled mornings', (tester) async {
    final gateway = FakeGateway();
    final prefs = MemoryPrefsStore({'morning_brief_enabled': 'true'});
    await _pump(tester, gateway, prefs);
    expect(
      tester.widget<SwitchListTile>(_switch('morning-brief-switch')).value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('morning-brief-switch')));
    await tester.pumpAndSettle();
    expect(prefs.values['morning_brief_enabled'], 'false');
    expect(gateway.cancelled.length, scheduleDays);
  });
}
