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
}
