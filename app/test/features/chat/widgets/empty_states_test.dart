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
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: SuggestedPrompts(onSelect: (p) => selected = p)),
        ),
      );

      expect(find.text('SUGGESTED'), findsOneWidget);
      final first = SuggestedPrompts.prompts.first.text;
      expect(find.text(first), findsOneWidget);
      await tester.tap(find.text(first));
      expect(selected, first);
    },
  );

  testWidgets(
    'SuggestedPrompts vision hint routes to library when no vision model',
    (tester) async {
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
}
