// Import preview dialog (gallery's file → parse → preview → save flow):
// a mocked, already-parsed card's fields render before anything is
// persisted, and Cancel/Import resolve the future correctly.

import 'dart:async';

import 'package:dhruva/data/characters/character_card.dart';
import 'package:dhruva/features/characters/widgets/import_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _mockedFields = ImportedCharacterFields(
  name: 'Aria',
  personaSystemPrompt: 'Aria is the night-shift barista at a 24hr cafe.',
  greeting: "We're technically closed, but sit anywhere.",
  exampleDialogues: ['User: hi\nAssistant: hey'],
  avatarEmoji: '☕',
);

void main() {
  Widget buildApp(VoidCallback onOpen) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showImportPreviewDialog(
                context,
                _mockedFields,
              );
              onOpen.call();
              // Surface the result via a Text widget so the test can find it.
              if (context.mounted) {
                unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (context) => Text('result:$result'),
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

  testWidgets('shows the parsed card\'s name, persona, and greeting', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Aria'), findsOneWidget);
    expect(
      find.text('Aria is the night-shift barista at a 24hr cafe.'),
      findsOneWidget,
    );
    expect(
      find.text("We're technically closed, but sit anywhere."),
      findsOneWidget,
    );
    expect(find.text('☕'), findsOneWidget);
  });

  testWidgets('Cancel resolves the future to false', (tester) async {
    await tester.pumpWidget(buildApp(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('result:false'), findsOneWidget);
  });

  testWidgets('Import resolves the future to true', (tester) async {
    await tester.pumpWidget(buildApp(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('result:true'), findsOneWidget);
  });
}
