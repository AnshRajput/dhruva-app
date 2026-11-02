// Draft reply as a real workflow: the user's own text is the only user bubble
// (labelled "Action: Draft a reply"), the instruction rides in the system
// layer, and the result opens an editable draft sheet with tone chips, Copy,
// Share, Open in the source app and Save. An omitted ask is named honestly.

import 'package:dhruva/core/actions/action_prompt.dart';
import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_health_fakes.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

class _Opener implements ExternalOpener {
  final launched = <String>[];
  @override
  Future<bool> launchApp(String package) async {
    launched.add(package);
    return true;
  }

  @override
  Future<void> openFile(String grantId, String entryId) async {}
}

const _message =
    'Marcus: Hi Meera, can you approve the budget by Friday? Also please '
    'review the vendor contract.';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/dhruva-draft-test.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  testWidgets('the prompt template never shows as the user bubble; the draft '
      'opens editable, with tones, omissions and Open in the source app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final modelId = await insertModel();
    final engine = FakeEngineService(
      scriptedTokens: const [
        'Hi ',
        'Marcus, ',
        'I ',
        'approved ',
        'the ',
        'budget.',
      ],
    );
    final opener = _Opener();
    final args = ChatRouteArgs(
      initialModelId: modelId,
      initialPrompt: _message,
      actionSystemPrompt: draftReplySystemPrompt('Warm'),
      sourcePackage: 'com.whatsapp',
      sourceApp: 'WhatsApp',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(engine),
          externalOpenerProvider.overrideWithValue(opener),
          ...deviceHealthTestOverrides(),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ChatThreadScreen(args: args),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The engine got the instruction as the SYSTEM turn and the user's own
    // text as the user turn.
    final turns = engine.lastMessages!;
    expect(turns.first.role, EngineRole.system);
    expect(turns.first.content, contains('Write a Warm reply'));
    expect(turns.last.role, EngineRole.user);
    expect(turns.last.content, _message);

    // The sheet opened by itself with the reply, editable.
    expect(find.byKey(const ValueKey('draft-sheet')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('draft-field')),
    );
    expect(field.controller!.text, 'Hi Marcus, I approved the budget.');
    // The ask the draft skipped is named.
    expect(
      find.text("Didn't cover: review the vendor contract"),
      findsOneWidget,
    );
    for (final t in ['Short', 'Warm', 'Formal']) {
      expect(find.byKey(ValueKey('draft-tone-$t')), findsOneWidget);
    }
    expect(find.text('Open in WhatsApp'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('draft-save')), findsOneWidget);

    // Open in the source app launches that package.
    await tester.tap(find.byKey(const ValueKey('draft-open-source')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(opener.launched, ['com.whatsapp']);

    // A tone chip rewrites through the same chat: the system layer changes.
    await tester.tap(find.byKey(const ValueKey('draft-tone-Formal')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(
      engine.lastMessages!.first.content,
      contains('Write a Formal reply'),
    );
    expect(engine.generateCount, 2);

    // Close the sheet: the thread shows the user's text under the label, and
    // never the instruction.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('action-label')), findsOneWidget);
    expect(find.text('Action: Draft a reply'), findsOneWidget);
    expect(find.textContaining('Write a Warm reply'), findsNothing);
    expect(find.textContaining('Write a Formal reply'), findsNothing);
    expect(find.textContaining('Output only the reply'), findsNothing);
    expect(find.text(_message), findsOneWidget);
    // The draft can be reopened from the thread.
    expect(find.byKey(const ValueKey('edit-draft')), findsOneWidget);
  });
}
