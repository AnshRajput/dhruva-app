import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/models_hub/state/voice_models_controller.dart';
import 'package:dhruva/features/models_hub/widgets/voice_model_tile.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');

Future<void> _pump(
  WidgetTester tester,
  VoiceModelState state, {
  VoidCallback? onDownload,
  VoidCallback? onDelete,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: VoiceModelTile(
          state: state,
          onDownload: onDownload ?? () {},
          onDelete: onDelete ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('notInstalled shows a download button that fires onDownload', (
    tester,
  ) async {
    var downloaded = false;
    await _pump(
      tester,
      VoiceModelState(entry: _entry, status: VoiceModelStatus.notInstalled),
      onDownload: () => downloaded = true,
    );

    expect(find.text(_entry.displayName), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    await tester.tap(find.byTooltip('Download'));
    expect(downloaded, isTrue);
  });

  testWidgets('downloading shows a progress bar, no action button', (
    tester,
  ) async {
    await _pump(
      tester,
      VoiceModelState(
        entry: _entry,
        status: VoiceModelStatus.downloading,
        progress: 0.4,
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Download'), findsNothing);
  });

  testWidgets('installed shows a checkmark and a delete button', (
    tester,
  ) async {
    var deleted = false;
    await _pump(
      tester,
      VoiceModelState(entry: _entry, status: VoiceModelStatus.installed),
      onDelete: () => deleted = true,
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    expect(deleted, isTrue);
  });

  testWidgets('failed shows the error text and a retry button', (tester) async {
    var retried = false;
    await _pump(
      tester,
      VoiceModelState(
        entry: _entry,
        status: VoiceModelStatus.failed,
        errorMessage: 'network error',
      ),
      onDownload: () => retried = true,
    );

    expect(find.text('network error'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry'));
    expect(retried, isTrue);
  });
}
