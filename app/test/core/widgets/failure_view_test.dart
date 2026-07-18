import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/widgets/failure_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ErrorStateView shows the typed message and a working Retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ErrorStateView(
            error: const NetworkOfflineFailure('x'),
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    // Designed, not a bare sentence: icon + title + typed body + Retry.
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining("You're offline"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('EmptyStateView renders its message and icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: EmptyStateView(
            message: 'Character not found.',
            icon: Icons.person_off_outlined,
          ),
        ),
      ),
    );

    expect(find.text('Character not found.'), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });
}
