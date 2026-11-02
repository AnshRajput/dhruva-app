// Wave 5 motion and chrome: the rules the Wave 4 motion gate asked for, pinned.
// Press feedback releases when a scroll takes over; page transitions stay under
// the 300 ms UI budget; perpetual loops stop under reduced motion; the status
// bar follows the theme; the iOS app bar turns to glass only once content
// scrolls under it; the lightbox dismisses with a swipe down.

import 'dart:io';

import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/brand_star.dart';
import 'package:dhruva/core/theme/page_transitions.dart';
import 'package:dhruva/core/widgets/edge_fade.dart';
import 'package:dhruva/core/widgets/platform_chrome.dart';
import 'package:dhruva/core/widgets/pressable_scale.dart';
import 'package:dhruva/features/chat/widgets/brand_motif.dart';
import 'package:dhruva/features/vision/widgets/image_lightbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale;

Widget _app(Widget child, {bool reduce = false, ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: c!,
      ),
      home: Scaffold(body: child),
    );

void main() {
  group('PressableScale', () {
    testWidgets('scales to 0.97 on pointer-down and back on release', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: PressableScale(
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        ),
      );
      expect(_scale(tester), 1);
      final g = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scale(tester), 0.97);
      await g.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scale(tester), 1);
      expect(taps, 1);
    });

    testWidgets('does not stay shrunk while a list scrolls', (tester) async {
      await tester.pumpWidget(
        _app(
          ListView(
            children: [
              for (var i = 0; i < 30; i++)
                PressableScale(
                  onTap: () {},
                  child: SizedBox(height: 80, child: Text('row $i')),
                ),
            ],
          ),
        ),
      );
      final g = await tester.startGesture(tester.getCenter(find.text('row 2')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .any((s) => s.scale == 0.97),
        isTrue,
      );
      // The finger drags: the scroll wins, the press must let go.
      await g.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widgetList<AnimatedScale>(find.byType(AnimatedScale))
            .every((s) => s.scale == 1),
        isTrue,
        reason: 'a scroll is not a press',
      );
      await g.up();
      await tester.pump();
    });

    testWidgets('reduced motion keeps the tap but drops the movement', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: PressableScale(
              onTap: () => taps++,
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
          reduce: true,
        ),
      );
      final g = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_scale(tester), 1);
      await g.up();
      expect(taps, 1);
    });
  });

  group('page transitions and ripple', () {
    test('Android pages move in under the 300 ms budget, exit faster', () {
      const b = DhruvaPageTransitionsBuilder();
      expect(b.transitionDuration, const Duration(milliseconds: 220));
      expect(b.reverseTransitionDuration, const Duration(milliseconds: 180));
      expect(
        b.transitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
      expect(b.reverseTransitionDuration, lessThan(b.transitionDuration));
      for (final t in [AppTheme.light, AppTheme.dark]) {
        expect(
          t.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<DhruvaPageTransitionsBuilder>(),
        );
        expect(
          t.pageTransitionsTheme.builders[TargetPlatform.iOS],
          isA<CupertinoPageTransitionsBuilder>(),
        );
        expect(t.splashFactory, InkRipple.splashFactory);
      }
    });

    testWidgets('a pushed Android page fades in with an 8 px rise', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.android),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('next page')),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      final early = tester.getTopLeft(find.text('next page')).dy;
      await tester.pump(const Duration(milliseconds: 250));
      final settled = tester.getTopLeft(find.text('next page')).dy;
      expect(early - settled, inInclusiveRange(1, 8.5));
      expect(tester.hasRunningAnimations, isFalse, reason: '220 ms is done');
    });
  });

  group('perpetual loops stop under reduced motion', () {
    testWidgets('turning reduced motion on while a loop runs stops it', (
      tester,
    ) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, c) => ValueListenableBuilder<bool>(
            valueListenable: reduce,
            builder: (context, r, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: r),
              child: c!,
            ),
          ),
          home: const Scaffold(body: Center(child: DhruvaLoader())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      reduce.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });

    for (final (name, loop) in <(String, Widget)>[
      ('the loader', const DhruvaLoader()),
      ('the typing dots', const TypingIndicator()),
    ]) {
      testWidgets('$name keep moving normally', (tester) async {
        await tester.pumpWidget(_app(Center(child: loop)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, isTrue);
      });

      testWidgets('$name rest when motion is reduced', (tester) async {
        await tester.pumpWidget(_app(Center(child: loop), reduce: true));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, isFalse);
        // And a screen holding them can settle (no perpetual frames).
        await tester.pumpAndSettle();
      });
    }
  });

  group('status bar', () {
    test('overlayStyleFor follows the theme', () {
      expect(
        AppTheme.light.appBarTheme.systemOverlayStyle,
        isA<SystemUiOverlayStyle>().having(
          (s) => s.statusBarIconBrightness,
          'icons',
          Brightness.dark,
        ),
      );
      expect(
        AppTheme.dark.appBarTheme.systemOverlayStyle,
        isA<SystemUiOverlayStyle>().having(
          (s) => s.statusBarIconBrightness,
          'icons',
          Brightness.light,
        ),
      );
    });

    testWidgets('the app root sets it for every route, light and dark', (
      tester,
    ) async {
      for (final (mode, icons) in [
        ('light', Brightness.dark),
        ('dark', Brightness.light),
      ]) {
        await pumpDhruvaApp(
          tester,
          prefs: MemoryPrefsStore({
            'theme_mode': mode,
            'what_moved_dismissed': 'true',
          }),
        );
        final region = tester
            .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first;
        expect(region.value.statusBarIconBrightness, icons, reason: mode);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('iOS app bar', () {
    testWidgets('clear at rest, glass only once content scrolls under it', (
      tester,
    ) async {
      final prefs = MemoryPrefsStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsStoreProvider.overrideWith((ref) async => prefs)],
          child: MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
            home: ChromeScaffold(
              appBar: const AdaptiveAppBar(title: Text('Title')),
              bodyBuilder: (context, inset) => ListView(
                padding: EdgeInsets.only(top: inset.top),
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final glass = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(BackdropFilter),
      );
      expect(glass, findsNothing, reason: 'content is not under it yet');

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(glass, findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(glass, findsNothing);
    });
  });

  group('image lightbox', () {
    final png = File('test/assets/red_64.png').readAsBytesSync();

    testWidgets('opens with a fade and a swipe down dismisses it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageLightbox(context, png),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.fling(
        find.byType(InteractiveViewer),
        const Offset(0, 400),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('the close button still works', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageLightbox(context, png),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });

  testWidgets('EdgeFade fades only the edge with more content', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          height: 48,
          child: EdgeFade(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 10; i++)
                  SizedBox(width: 120, child: Text('chip $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);
    // Scrolling to the end must not throw and keeps the row usable.
    await tester.drag(find.byType(ListView), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('chip 9'), findsOneWidget);
  });
}
