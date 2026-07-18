// About page (UX-amendment follow-up): renders app identity + version,
// the pull quotes, and every link row fires url_launcher with the right
// URL — proven against a fake UrlLauncherPlatform, same harness shape as
// settings_screen_test.dart.

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/settings/ui/about_screen.dart';
import 'package:flutter/material.dart';
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
  late _FakeUrlLauncher fakeLauncher;
  final realLauncher = UrlLauncherPlatform.instance;

  setUp(() {
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = realLauncher;
  });

  Future<void> pump(WidgetTester tester) async {
    // The page's whole point is to be a long, unhurried scroll (pull
    // quotes + developer block + links) — taller than the default 600px
    // test surface. Widen it so every row is actually laid out and
    // tappable instead of scrolling to find each one.
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const AboutScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows app identity, version and every pull quote', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Dhruva AI'), findsOneWidget);
    // DESIGNER BLOCKING #3: the name's own meaning, in its own script.
    expect(find.text('ध्रुव'), findsOneWidget);
    expect(find.text('Version 0.2.5 (build 5)'), findsOneWidget);
    expect(
      find.textContaining('Your AI. Your phone. Nobody else’s business.'),
      findsOneWidget,
    );
    expect(find.textContaining('Dhruva sat still'), findsOneWidget);
    expect(find.textContaining('Every model you run here'), findsOneWidget);
  });

  testWidgets('developer credit block names the developer and studio', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('Ansh Singh Rajput'), findsWidgets);
    expect(find.textContaining('Appu Inside Engineering'), findsOneWidget);
  });

  testWidgets('credit row launches the portfolio URL', (tester) async {
    await pump(tester);

    await tester.tap(find.text(' by Ansh Singh Rajput'));
    await tester.pumpAndSettle();

    expect(fakeLauncher.launched, contains('https://anshgandharva.online'));
  });

  testWidgets('GitHub row launches the repo URL', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Source on GitHub'));
    await tester.pumpAndSettle();

    expect(
      fakeLauncher.launched,
      contains('https://github.com/AnshRajput/dhruva-app'),
    );
  });

  testWidgets('Website row launches the deployed site URL', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Website'));
    await tester.pumpAndSettle();

    expect(fakeLauncher.launched, contains('https://dhruvaai.vercel.app'));
  });

  testWidgets('License row launches the LICENSE file URL', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Apache License 2.0'));
    await tester.pumpAndSettle();

    expect(
      fakeLauncher.launched,
      contains('https://github.com/AnshRajput/dhruva-app/blob/main/LICENSE'),
    );
  });

  testWidgets('privacy one-liner is present', (tester) async {
    await pump(tester);

    expect(find.textContaining('Zero telemetry'), findsOneWidget);
  });
}
