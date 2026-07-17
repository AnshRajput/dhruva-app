import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/composer.dart';
import 'package:dhruva/features/voice/widgets/mic_button.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../voice/voice_test_helpers.dart';

void main() {
  late Directory tmp;
  late FakeMicSource mic;
  late FakeVoiceService voice;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('composer_test_');
    mic = FakeMicSource();
    voice = FakeVoiceService(scriptedTranscript: 'hello world');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // `MaterialApp.router` (not a bare `MaterialApp`) so the mic button's
  // "no model" / hold-to-talk-finalize paths — which route through
  // `context.push` — have a real `GoRouter` to push against; `/models`
  // resolves to a stand-in screen so the push is observable.
  Future<void> pumpComposer(
    WidgetTester tester, {
    required bool isGenerating,
    required ValueChanged<String> onSend,
    VoidCallback? onCancel,
    VoidCallback? onOpenSettings,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Composer(
              isGenerating: isGenerating,
              onSend: onSend,
              onCancel: onCancel ?? () {},
              onOpenSettings: onOpenSettings ?? () {},
            ),
          ),
        ),
        GoRoute(
          path: '/models',
          builder: (context, state) =>
              const Scaffold(body: Text('models hub stand-in')),
        ),
      ],
    );
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceModelInstallerProvider.overrideWith(
            (ref) async => VoiceModelInstaller(modelsDirectory: tmp),
          ),
          voiceServiceProvider.overrideWithValue(voice),
          micSourceProvider.overrideWithValue(mic),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
  }

  testWidgets(
    'send button is disabled with empty text, enabled once text is typed',
    (tester) async {
      await pumpComposer(tester, isGenerating: false, onSend: (_) {});

      final sendButton = tester.widget<IconButton>(
        find.byType(IconButton).last,
      );
      expect(sendButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      final enabledButton = tester.widget<IconButton>(
        find.byType(IconButton).last,
      );
      expect(enabledButton.onPressed, isNotNull);
    },
  );

  testWidgets('tapping send fires onSend and clears the field', (tester) async {
    String? sent;
    await pumpComposer(
      tester,
      isGenerating: false,
      onSend: (text) => sent = text,
    );

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byType(IconButton).last);
    await tester.pump();

    expect(sent, 'hello');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('generating shows a stop button that fires onCancel', (
    tester,
  ) async {
    var cancelled = false;
    await pumpComposer(
      tester,
      isGenerating: true,
      onSend: (_) {},
      onCancel: () => cancelled = true,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    expect(cancelled, isTrue);
  });

  testWidgets('sliders icon opens settings', (tester) async {
    var opened = false;
    await pumpComposer(
      tester,
      isGenerating: false,
      onSend: (_) {},
      onOpenSettings: () => opened = true,
    );

    await tester.tap(find.byIcon(Icons.tune));
    expect(opened, isTrue);
  });

  // `endHold` chains several stream-close hops (mic controller close ->
  // `segment()`'s `await for` noticing it -> `transcribeStream`'s `await
  // for` noticing THAT -> this widget's `.listen` `onDone` -> a completer)
  // before the composer's field actually updates — a couple of pumps isn't
  // reliably enough turns of the microtask queue to drain all of them.
  Future<void> pumpUntilSettled(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('hold-to-talk (Loop 6, D1)', () {
    testWidgets(
      'live transcript renders while held, release finalizes it into the '
      'field editable — never auto-sent',
      (tester) async {
        installAllVoiceModels(tmp);
        String? sent;
        await pumpComposer(
          tester,
          isGenerating: false,
          onSend: (text) => sent = text,
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MicButton)),
        );
        await tester.pump();
        expect(find.text('Listening…'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);

        mic.pushSpeech();
        mic.pushSilence();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('hello world'), findsOneWidget);

        await gesture.up();
        await pumpUntilSettled(tester);

        expect(sent, isNull, reason: 'hold-to-talk never auto-sends');
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'hello world',
        );
      },
    );

    testWidgets(
      'typed text is preserved and appended to, not overwritten, by a '
      'follow-up hold',
      (tester) async {
        installAllVoiceModels(tmp);
        await pumpComposer(tester, isGenerating: false, onSend: (_) {});

        await tester.enterText(find.byType(TextField), 'reminder:');
        await tester.pump();

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(MicButton)),
        );
        await tester.pump();
        mic.pushSpeech();
        mic.pushSilence();
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await pumpUntilSettled(tester);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'reminder: hello world',
        );
      },
    );

    testWidgets(
      'no voice models installed -> mic press routes to the models hub',
      (tester) async {
        // `tmp` is empty — no voice models installed. A plain `tap` (not a
        // held gesture) is enough — `startHold` resolves to `noModel`
        // before there's anything to hold for.
        await pumpComposer(tester, isGenerating: false, onSend: (_) {});

        await tester.tap(find.byType(MicButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('models hub stand-in'), findsOneWidget);
      },
    );

    testWidgets(
      'mic permission denied shows a clear message, not a dead recording '
      'state',
      (tester) async {
        installAllVoiceModels(tmp);
        mic.permissionGranted = false;
        await pumpComposer(tester, isGenerating: false, onSend: (_) {});

        await tester.tap(find.byType(MicButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          find.textContaining('Microphone access is required'),
          findsOneWidget,
        );
        expect(find.text('Listening…'), findsNothing);
      },
    );
  });
}
