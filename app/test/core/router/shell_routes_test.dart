// Daily-assistant shell + router (Wave 1): every pre-redesign route lands on
// its new home, no shell tab renders blank, and nothing outside the shell
// pushes a shell-branch route (the 0.6.0 blank-page bug class).

import 'dart:io';

import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/main.dart' show navigateFromIntent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/app_harness.dart';

void main() {
  group('legacyRouteRedirect (pure)', () {
    String? r(String uri) => legacyRouteRedirect(Uri.parse(uri));

    test('every old tab route maps to its new home', () {
      expect(r('/'), '/today');
      expect(r('/chat'), '/ask');
      expect(r('/characters'), '/personas');
      expect(r('/models'), '/settings/models');
      expect(r('/playground'), '/settings/models/compare');
      expect(r('/workflows'), '/actions');
    });

    test('query strings survive (share sheet text, voice tab, news tab)', () {
      expect(r('/workflows?text=hi+there'), '/actions?text=hi+there');
      expect(r('/workflows?id=summarize'), '/actions?id=summarize');
      expect(r('/models?tab=voice'), '/settings/models?tab=voice');
      expect(r('/playground?tab=news'), '/settings/models/compare?tab=news');
    });

    test('trailing slash is tolerated', () {
      expect(r('/chat/'), '/ask');
    });

    test('current and deep routes are left alone', () {
      for (final path in [
        '/today',
        '/inbox',
        '/ask',
        '/library',
        '/settings',
        '/settings/models',
        '/actions',
        '/personas',
        '/chat/42',
        '/chat/new',
        '/characters/3',
        '/characters/new',
        '/models/hub',
        '/models/downloads',
        '/models/repo/a%2Fb',
        '/settings/about',
      ]) {
        expect(r(path), isNull, reason: path);
      }
    });

    test('isShellLocation recognises only the four tab branches', () {
      for (final tab in ['/today', '/inbox', '/ask', '/library']) {
        expect(isShellLocation(tab), isTrue, reason: tab);
      }
      expect(isShellLocation('/ask?x=1'), isTrue);
      for (final other in [
        '/inbox/connect',
        '/settings',
        '/actions',
        '/chat/new',
        '/models/hub',
      ]) {
        expect(isShellLocation(other), isFalse, reason: other);
      }
    });
  });

  group('old routes land correctly in the real app', () {
    Future<void> landOn(
      WidgetTester tester,
      String oldRoute,
      Finder expected,
    ) async {
      await pumpDhruvaApp(tester, location: oldRoute);
      expect(tester.takeException(), isNull);
      expect(expected, findsWidgets, reason: '$oldRoute should render');
    }

    testWidgets('/chat -> Ask tab', (tester) async {
      await landOn(tester, '/chat', find.byTooltip('Personas'));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('/characters -> Personas gallery', (tester) async {
      await landOn(
        tester,
        '/characters',
        find.widgetWithText(AppBar, 'Personas'),
      );
    });

    testWidgets('/models -> Models hub under Settings', (tester) async {
      await landOn(tester, '/models', find.text('Discover'));
    });

    testWidgets('/models?tab=voice opens the Voice tab', (tester) async {
      await pumpDhruvaApp(tester, location: '/models?tab=voice', settle: false);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(
        DefaultTabController.of(tester.element(find.byWidget(tabs))).index,
        2,
      );
    });

    testWidgets('/playground -> Compare models', (tester) async {
      await landOn(
        tester,
        '/playground',
        find.widgetWithText(AppBar, 'Compare models'),
      );
    });

    testWidgets('/playground?tab=news opens AI news', (tester) async {
      await pumpDhruvaApp(tester, location: '/playground?tab=news');
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(
        DefaultTabController.of(tester.element(find.byWidget(tabs))).index,
        1,
      );
    });

    testWidgets('/settings -> Settings, full-screen (no tab bar)', (
      tester,
    ) async {
      await landOn(tester, '/settings', find.text('Appearance'));
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('/workflows?text= -> Actions with the shared text prefilled', (
      tester,
    ) async {
      await landOn(
        tester,
        '/workflows?text=hello+world',
        find.widgetWithText(AppBar, 'Actions'),
      );
      expect(find.text('Text ready. Pick what to do with it.'), findsOneWidget);
    });

    testWidgets('/workflows?id=summarize opens that action sheet', (
      tester,
    ) async {
      await pumpDhruvaApp(tester, location: '/workflows?id=summarize');
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('/ -> Today', (tester) async {
      await landOn(tester, '/', find.text('Your brief'));
    });

    testWidgets('/chat/:id still opens a thread route', (tester) async {
      await pumpDhruvaApp(tester, location: '/chat/999999');
      expect(tester.takeException(), isNull);
      expect(find.text('No model installed yet'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('no blank shells', () {
    testWidgets('each tab branch renders its own content', (tester) async {
      final expectations = <String, String>{
        '/today': 'Your brief',
        '/inbox': 'Your inbox, in one calm list',
        '/ask': 'Ask',
        '/library': 'Documents',
      };
      for (final entry in expectations.entries) {
        await pumpDhruvaApp(tester, location: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
        expect(find.text(entry.value), findsWidgets, reason: entry.key);
        expect(find.byType(NavigationBar), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('Inbox tab is hidden while no inbox source exists', (
      tester,
    ) async {
      await pumpDhruvaApp(tester);
      final bar = find.byType(NavigationBar);
      expect(
        find.descendant(of: bar, matching: find.text('Inbox')),
        findsNothing,
      );
      for (final label in ['Today', 'Ask', 'Library']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
        );
      }
    });

    testWidgets('pushing out-of-shell routes never builds a second shell', (
      tester,
    ) async {
      await pumpDhruvaApp(tester);
      for (final route in [
        '/settings',
        '/settings/models',
        '/settings/models/compare',
        '/settings/connectors',
        '/actions',
        '/personas',
        '/day',
        '/inbox/connect',
        '/models/hub',
      ]) {
        appRouter.go('/today');
        await tester.pumpAndSettle();
        // ignore: unawaited_futures
        appRouter.push(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        expect(find.byType(NavigationBar), findsNothing, reason: route);
        // Back returns to the single Today shell.
        appRouter.pop();
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget, reason: route);
        expect(find.text('Your brief'), findsOneWidget, reason: route);
      }
    });

    testWidgets('an intent that targets a shell tab uses go, not push', (
      tester,
    ) async {
      await pumpDhruvaApp(tester);
      navigateFromIntent('/ask');
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byTooltip('Personas'), findsOneWidget);

      // And a non-shell intent (share sheet) pushes a full-screen route.
      navigateFromIntent('/actions?text=hi');
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
    });

    testWidgets(
      'Settings > Models > Downloads chain opens full-screen routes',
      (tester) async {
        await pumpDhruvaApp(tester);
        await tester.tap(find.byKey(const ValueKey('today-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-models')));
        // The hub's loaders animate forever: pump a fixed span, don't settle.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byTooltip('Downloads'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsNothing);
      },
    );
  });

  test('sweep: nothing in lib/ pushes a shell-branch route', () {
    final shellPush = RegExp(
      r'''(?:push|pushReplacement|pushNamed)\(\s*['"]/(?:today|inbox|ask|library)(?:['"?])''',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (shellPush.hasMatch(text)) offenders.add(f.path);
    }
    expect(offenders, isEmpty, reason: 'use go(), or a full-screen route');
  });

  test('sweep: nothing in lib/ still targets a legacy tab route directly', () {
    // Old routes keep working via redirects, but first-party code should use
    // the new homes so redirects stay a compatibility layer, not a crutch.
    final legacy = RegExp(
      r'''(?:push|go|pushReplacement)\(\s*['"]/(?:chat|characters|models|playground|workflows)(?:['"?])''',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (legacy.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });

  testWidgets('appRouter exposes only the four tab branches as the shell', (
    tester,
  ) async {
    final shell = appRouter.configuration.routes
        .whereType<StatefulShellRoute>()
        .single;
    expect(shell.branches, hasLength(4));
  });
}
