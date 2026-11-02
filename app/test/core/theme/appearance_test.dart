// Appearance (daily-assistant Wave 1): follow system light/dark by default, a
// Settings > Appearance control (System/Light/Dark) that persists, and a
// light theme whose text pairs meet WCAG AA.

import 'dart:io';

import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/appearance_providers.dart';
import 'package:dhruva/features/settings/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('FilePrefsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dhruva_prefs_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('round-trips values across instances (persistence)', () async {
      await FilePrefsStore(dir).write('theme_mode', 'dark');
      await FilePrefsStore(dir).write('other', 'x');
      final again = FilePrefsStore(dir);
      expect(await again.read('theme_mode'), 'dark');
      expect(await again.read('other'), 'x');
      expect(await again.read('missing'), isNull);
    });

    test('a corrupt file reads as empty instead of throwing', () async {
      File('${dir.path}/app_prefs_v1.json').writeAsStringSync('{not json');
      expect(await FilePrefsStore(dir).read('theme_mode'), isNull);
    });
  });

  group('themeModeProvider', () {
    test('defaults to following the system', () async {
      final c = ProviderContainer(
        overrides: [
          prefsStoreProvider.overrideWith((ref) async => MemoryPrefsStore()),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(themeModeProvider.future), ThemeMode.system);
    });

    test('set() persists and a fresh container reads it back', () async {
      final store = MemoryPrefsStore();
      ProviderContainer make() => ProviderContainer(
        overrides: [prefsStoreProvider.overrideWith((ref) async => store)],
      );
      final first = make();
      addTearDown(first.dispose);
      await first.read(themeModeProvider.future);
      await first.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(store.values['theme_mode'], 'dark');

      final second = make();
      addTearDown(second.dispose);
      expect(await second.read(themeModeProvider.future), ThemeMode.dark);
    });

    test('parseThemeMode falls back to system for junk', () {
      expect(parseThemeMode('light'), ThemeMode.light);
      expect(parseThemeMode('dark'), ThemeMode.dark);
      expect(parseThemeMode('sepia'), ThemeMode.system);
      expect(parseThemeMode(null), ThemeMode.system);
    });
  });

  group('the app follows the saved mode', () {
    testWidgets('no saved choice: ThemeMode.system', (tester) async {
      await pumpDhruvaApp(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
    });

    testWidgets('a saved Dark choice is applied at startup', (tester) async {
      await pumpDhruvaApp(
        tester,
        prefs: MemoryPrefsStore({
          'theme_mode': 'dark',
          'what_moved_dismissed': 'true',
        }),
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });
  });

  group('Settings > Appearance (inline)', () {
    testWidgets('System / Light / Dark control persists the choice', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore({'what_moved_dismissed': 'true'});
      await pumpDhruvaApp(tester, location: '/settings', prefs: prefs);

      final control = find.byKey(const ValueKey('appearance-segments'));
      expect(control, findsOneWidget);
      for (final label in ['System', 'Light', 'Dark']) {
        expect(
          find.descendant(of: control, matching: find.text(label)),
          findsOneWidget,
        );
      }

      await tester.tap(
        find.descendant(of: control, matching: find.text('Dark')),
      );
      await tester.pumpAndSettle();
      expect(prefs.values['theme_mode'], 'dark');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await tester.tap(
        find.descendant(of: control, matching: find.text('Light')),
      );
      await tester.pumpAndSettle();
      expect(prefs.values['theme_mode'], 'light');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
    });

    testWidgets('reduce-transparency switch only appears on iOS', (
      tester,
    ) async {
      Future<void> pumpOn(TargetPlatform p, MemoryPrefsStore prefs) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(), // fresh provider state per platform
            overrides: [prefsStoreProvider.overrideWith((ref) async => prefs)],
            child: MaterialApp(
              theme: AppTheme.dark.copyWith(platform: p),
              home: const SettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpOn(TargetPlatform.android, MemoryPrefsStore());
      expect(
        find.byKey(const ValueKey('reduce-transparency-switch')),
        findsNothing,
      );

      final prefs = MemoryPrefsStore();
      await pumpOn(TargetPlatform.iOS, prefs);
      final sw = find.byKey(const ValueKey('reduce-transparency-switch'));
      expect(sw, findsOneWidget);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(prefs.values['reduce_transparency'], 'true');
    });
  });

  group('light theme contrast (WCAG AA 4.5:1 for text pairs)', () {
    final s = AppTheme.light.colorScheme;
    final pairs = <String, (Color, Color)>{
      'onSurface/surface': (s.onSurface, s.surface),
      'onSurface/background': (
        s.onSurface,
        AppTheme.light.scaffoldBackgroundColor,
      ),
      'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
      'onSurfaceVariant/background': (
        s.onSurfaceVariant,
        AppTheme.light.scaffoldBackgroundColor,
      ),
      'primary/surface (gold link text)': (s.primary, s.surface),
      'primary/background': (s.primary, AppTheme.light.scaffoldBackgroundColor),
      'onPrimary/primary (filled button)': (s.onPrimary, s.primary),
      'onPrimaryContainer/primaryContainer (nav pill)': (
        s.onPrimaryContainer,
        s.primaryContainer,
      ),
      'onSecondaryContainer/secondaryContainer': (
        s.onSecondaryContainer,
        s.secondaryContainer,
      ),
      'error/surface': (s.error, s.surface),
      'onError/error': (s.onError, s.error),
      'onInverseSurface/inverseSurface (snackbar)': (
        s.onInverseSurface,
        s.inverseSurface,
      ),
    };
    for (final e in pairs.entries) {
      test(e.key, () {
        expect(
          _contrast(e.value.$1, e.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      });
    }

    test('outline (non-text UI) meets 3:1 on surface', () {
      expect(_contrast(s.outline, s.surface), greaterThanOrEqualTo(3.0));
    });
  });

  group('Rule 6 shape tokens (Android Material 3 Expressive)', () {
    test('nav indicator, FAB and buttons are stadium/pill from the theme', () {
      for (final t in [AppTheme.light, AppTheme.dark]) {
        expect(t.navigationBarTheme.indicatorShape, isA<StadiumBorder>());
        expect(t.floatingActionButtonTheme.shape, isA<StadiumBorder>());
        final chip = t.chipTheme.shape! as RoundedRectangleBorder;
        expect(
          (chip.borderRadius as BorderRadius).topLeft.x,
          greaterThanOrEqualTo(9999),
        );
      }
    });
  });
}
