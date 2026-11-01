import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/empty_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NoModelInstalledView shows copy + CTA and fires callback', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NoModelInstalledView(onBrowseModels: () => tapped = true),
        ),
      ),
    );

    expect(find.text('No model installed yet'), findsOneWidget);
    expect(find.text('Browse models'), findsOneWidget);
    // Value made explicit + brand tagline (VIDEO_FIXES #6).
    expect(find.textContaining('runs entirely on your phone'), findsOneWidget);
    expect(
      find.text("Your AI. Your phone. Nobody else's business."),
      findsOneWidget,
    );
    await tester.tap(find.text('Browse models'));
    expect(tapped, isTrue);
  });

  testWidgets('NoConversationsView shows copy, trust mark, and CTA', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NoConversationsView(onNewChat: () => tapped = true),
        ),
      ),
    );

    expect(find.text('Start your first conversation'), findsOneWidget);
    expect(find.text('Runs 100% on your device'), findsOneWidget);
    await tester.tap(find.text('New chat'));
    expect(tapped, isTrue);
  });

  testWidgets(
    'SuggestedPrompts tapping a starter fires onSelect with its text',
    (tester) async {
      _tall(tester);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SuggestedPrompts(onSelect: (p) => selected = p)),
        ),
      );

      expect(find.text('What can I ask?'), findsOneWidget);
      final first = SuggestedPrompts.prompts.first.text;
      expect(find.text(first), findsOneWidget);
      await tester.tap(find.text(first));
      expect(selected, first);
    },
  );

  testWidgets(
    'SuggestedPrompts vision hint routes to library when no vision model',
    (tester) async {
      _tall(tester);
      var getVision = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SuggestedPrompts(
              onSelect: (_) {},
              onGetVisionModel: () => getVision = true,
            ),
          ),
        ),
      );

      final hint = find.text('Get a vision model to analyze photos');
      expect(hint, findsOneWidget);
      await tester.tap(hint);
      expect(getVision, isTrue);
    },
  );

  testWidgets('SuggestedPrompts vision hint offers to switch when installed', (
    tester,
  ) async {
    _tall(tester);
    var switched = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SuggestedPrompts(
            onSelect: (_) {},
            hasVisionModelInstalled: true,
            onGetVisionModel: () {},
            onSwitchModel: () => switched = true,
          ),
        ),
      ),
    );

    final hint = find.text('Switch to your vision model to analyze photos');
    expect(hint, findsOneWidget);
    await tester.tap(hint);
    expect(switched, isTrue);
  });

  testWidgets(
    'SuggestedPrompts vision hint points at attach button when multimodal',
    (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SuggestedPrompts(
              onSelect: (_) {},
              isMultimodal: true,
              onGetVisionModel: () {},
            ),
          ),
        ),
      );

      expect(
        find.text('Tap the photo button below to analyze an image.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('What can I ask? offers 4-6 starters across writing, '
      'summarizing, planning and explaining, plus a connect hint', (
    tester,
  ) async {
    _tall(tester);
    var connect = 0;
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SuggestedPrompts(
            onSelect: picked.add,
            onOpenConnect: () => connect++,
          ),
        ),
      ),
    );

    expect(SuggestedPrompts.prompts.length, inInclusiveRange(4, 6));
    for (final topic in ['Writing', 'Summarizing', 'Planning', 'Explaining']) {
      expect(find.text(topic), findsWidgets, reason: topic);
    }
    for (final p in SuggestedPrompts.prompts) {
      expect(find.text(p.text), findsOneWidget);
    }
    // Hint: connecting calendar / folder unlocks more; it is tappable.
    final hint = find.byKey(const ValueKey('connect-hint'));
    expect(hint, findsOneWidget);
    expect(find.textContaining('calendar or a folder'), findsOneWidget);
    await tester.tap(hint);
    expect(connect, 1);
    // Nothing is sent until the user taps a starter.
    expect(picked, isEmpty);
  });

  testWidgets('the connect hint is plain text when nothing can open yet', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: SuggestedPrompts(onSelect: (_) {})),
      ),
    );
    expect(find.textContaining('calendar or a folder'), findsOneWidget);
  });
}

/// A phone-sized surface: the starters + hints are taller than the default
/// 800x600 test view.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
