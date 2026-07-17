import 'dart:async';

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/characters/widgets/emoji_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp() {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final emoji = await showEmojiPickerSheet(context);
              if (context.mounted) {
                unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (context) => Text('picked:$emoji'),
                  ),
                );
              }
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping an emoji resolves the sheet to that emoji', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Choose an avatar'), findsOneWidget);
    await tester.tap(find.text('🙂'));
    await tester.pumpAndSettle();

    expect(find.text('picked:🙂'), findsOneWidget);
  });

  testWidgets('dismissing without picking resolves to null', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap outside the sheet (the barrier) to dismiss.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('picked:null'), findsOneWidget);
  });
}
