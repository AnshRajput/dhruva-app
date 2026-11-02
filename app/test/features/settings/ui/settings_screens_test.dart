// Wave 2C settings surfaces: home grouping/order, About me, Privacy,
// Notifications, About order (D9). Each runs against a MemoryPrefsStore.

import 'package:dhruva/core/profile/user_profile.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/settings/privacy_facts.dart';
import 'package:dhruva/features/settings/ui/about_me_screen.dart';
import 'package:dhruva/features/settings/ui/about_screen.dart';
import 'package:dhruva/features/settings/ui/notifications_screen.dart';
import 'package:dhruva/features/settings/ui/privacy_screen.dart';
import 'package:dhruva/features/settings/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../support/app_harness.dart';

class _FakeLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
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
  final realLauncher = UrlLauncherPlatform.instance;
  late _FakeLauncher launcher;

  setUp(() {
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
  });
  tearDown(() => UrlLauncherPlatform.instance = realLauncher);

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    MemoryPrefsStore? prefs,
    Future<PrefsStore> Function()? prefsLoader,
  }) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsStoreProvider.overrideWith(
            (ref) async => prefsLoader != null
                ? await prefsLoader()
                : (prefs ?? MemoryPrefsStore()),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Settings home', () {
    testWidgets('rows are in the agreed order, each with a description', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());
      const order = [
        'Connectors',
        'About me',
        'Models & downloads',
        'Appearance',
        'Notifications',
        'Privacy',
        'Safety & reports',
        'Crash reports',
        'About Dhruva AI',
      ];
      double? last;
      for (final t in order) {
        final y = tester.getTopLeft(find.text(t).first).dy;
        if (last != null) expect(y, greaterThan(last), reason: t);
        last = y;
      }
      // Every navigation row has a non-empty one-line description.
      for (final key in [
        'settings-connectors',
        'settings-about-me',
        'settings-models',
        'settings-appearance',
        'settings-notifications',
        'settings-privacy',
        'settings-safety',
        'settings-crash-reports',
      ]) {
        final tile = tester.widget<ListTile>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(ListTile),
          ),
        );
        expect(tile.subtitle, isNotNull, reason: key);
        final sub = (tile.subtitle! as Text).data;
        expect(sub, isNotEmpty, reason: key);
      }
    });

    testWidgets('new rows open their screens', (tester) async {
      await pumpDhruvaApp(tester, location: '/settings');
      for (final (key, title) in [
        ('settings-about-me', 'Name'),
        ('settings-privacy', 'There is no Dhruva server.'),
        ('settings-notifications', 'Download alerts'),
        ('settings-appearance', 'System'),
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.text(title), findsWidgets, reason: key);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  });

  group('About me', () {
    testWidgets('saves locally and feeds the prompt-context builder', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore();
      await pump(tester, const AboutMeScreen(), prefs: prefs);

      // Nothing to save yet, nothing to clear, no preview.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('about-me-save')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('about-me-preview')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('about-me-name')),
        'Asha',
      );
      await tester.enterText(
        find.byKey(const ValueKey('about-me-role')),
        'nurse',
      );
      await tester.tap(find.byKey(const ValueKey('about-me-tone-Warm')));
      await tester.enterText(
        find.byKey(const ValueKey('about-me-signature')),
        'Thanks,\nAsha',
      );
      await tester.pumpAndSettle();

      // Live preview shows exactly what will be added.
      final preview = tester.widget<Text>(
        find.byKey(const ValueKey('about-me-preview')),
      );
      expect(preview.data, contains('- Name: Asha'));
      expect(preview.data, contains('- Writing style they like: Warm'));

      await tester.tap(find.byKey(const ValueKey('about-me-save')));
      await tester.pumpAndSettle();
      expect(find.text('Saved on this phone.'), findsOneWidget);

      final saved = UserProfile.fromRaw(prefs.values['user_profile']);
      expect(saved.name, 'Asha');
      expect(saved.role, 'nurse');
      expect(saved.tone, 'Warm');
      expect(saved.signature, 'Thanks,\nAsha');
      // Save is disabled again until something changes.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('about-me-save')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('shows the saved profile and Clear empties the form', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore({
        'user_profile':
            '{"name":"Ravi","role":"","tone":"Formal",'
            '"signature":""}',
      });
      await pump(tester, const AboutMeScreen(), prefs: prefs);
      expect(find.text('Ravi'), findsOneWidget);
      final formal = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('about-me-tone-Formal')),
      );
      expect(formal.selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('about-me-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi'), findsNothing);
      // Clearing is a draft change; saving it stores an empty profile.
      await tester.tap(find.byKey(const ValueKey('about-me-save')));
      await tester.pumpAndSettle();
      expect(UserProfile.fromRaw(prefs.values['user_profile']).isEmpty, isTrue);
    });

    testWidgets('loading state is a skeleton, not a spinner', (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Future<void>.delayed(const Duration(seconds: 5));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsStoreProvider.overrideWith((ref) async {
              await gate;
              return MemoryPrefsStore();
            }),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const AboutMeScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('about-me-loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-me-name')), findsOneWidget);
    });

    testWidgets('unreadable saved details say so and the form still works', (
      tester,
    ) async {
      await pump(
        tester,
        const AboutMeScreen(),
        prefsLoader: () async => throw 'disk',
      );
      expect(find.textContaining("Couldn't read your saved"), findsOneWidget);
      expect(find.byKey(const ValueKey('about-me-name')), findsOneWidget);
    });
  });

  group('Privacy', () {
    testWidgets('states the exact network facts, storage and backups', (
      tester,
    ) async {
      await pump(tester, const PrivacyScreen());
      expect(find.text(noServerFact), findsOneWidget);
      for (final f in networkFacts) {
        expect(find.text(f.title), findsOneWidget);
        expect(find.text(f.body), findsOneWidget);
      }
      expect(find.text('Hugging Face'), findsNothing); // inside body text
      expect(find.textContaining('Hugging Face'), findsOneWidget);
      expect(find.text('Cloud backup'), findsOneWidget);
      expect(find.text(backupsOffFact), findsOneWidget);
      expect(find.text(storedOnPhoneFact), findsOneWidget);
    });

    testWidgets('app switcher switch defaults off, persists, reaches native', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app.dhruva/privacy'),
        (c) async {
          calls.add(c);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('app.dhruva/privacy'),
          null,
        ),
      );
      final prefs = MemoryPrefsStore({'what_moved_dismissed': 'true'});
      await pumpDhruvaApp(tester, location: '/settings/privacy', prefs: prefs);
      final row = find.byKey(const ValueKey('hide-in-switcher-switch'));
      final sw = find.descendant(
        of: row,
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(prefs.values['hide_in_app_switcher'], 'true');
      expect(calls.last.method, 'setHideInSwitcher');
      expect(calls.last.arguments, true);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(prefs.values['hide_in_app_switcher'], 'false');
      expect(calls.last.arguments, false);
    });

    testWidgets('home widget title switch defaults on and persists', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore();
      await pump(tester, const PrivacyScreen(), prefs: prefs);
      final row = find.byKey(const ValueKey('widget-next-event-switch'));
      final sw = find.descendant(
        of: row,
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(prefs.values['widget_show_next_event'], 'false');
    });

    testWidgets('privacy policy row opens the policy URL', (tester) async {
      await pump(tester, const PrivacyScreen());
      await tester.tap(find.byKey(const ValueKey('privacy-policy-row')));
      await tester.pumpAndSettle();
      expect(launcher.launched, [
        'https://github.com/AnshRajput/dhruva-app/blob/main/docs/privacy.md',
      ]);
    });
  });

  group('Notifications', () {
    testWidgets('download alerts default on and persist when turned off', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore();
      await pump(tester, const NotificationsScreen(), prefs: prefs);
      final row = find.byKey(const ValueKey('download-alerts-switch'));
      final sw = find.descendant(
        of: row,
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(prefs.values['download_notifications'], 'false');
    });
  });

  group('About (D9 order)', () {
    testWidgets('version first, privacy and links next, manifesto last', (
      tester,
    ) async {
      await pump(tester, const AboutScreen());
      double y(Finder f) => tester.getTopLeft(f.first).dy;
      final version = y(find.textContaining('Version '));
      final privacy = y(find.text('Zero telemetry'));
      final links = y(find.text('Source on GitHub'));
      final story = y(find.textContaining('Dhruva sat still'));
      expect(version, lessThan(privacy));
      expect(privacy, lessThan(links));
      expect(links, lessThan(story));
      expect(y(find.text('ध्रुव')), greaterThan(links));
    });
  });
}
