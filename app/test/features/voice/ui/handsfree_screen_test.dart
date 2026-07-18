import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/voice/ui/handsfree_screen.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:dhruva/voice/fake_mic_source.dart';
import 'package:dhruva/voice/fake_voice_service.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../voice_test_helpers.dart';

void main() {
  late Directory tmp;
  late FakeMicSource mic;
  late FakeVoiceService voice;
  late FakeAudioSink sink;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('handsfree_screen_test_');
    mic = FakeMicSource();
    voice = FakeVoiceService(scriptedTranscript: 'hello there');
    sink = FakeAudioSink();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // `HandsFreeScreen` is always reached via `context.push` from an existing
  // chat screen in the real app (`ChatThreadScreen._openHandsFree`) — its
  // own exit button pops back to whatever pushed it. Pushing it from a
  // stand-in `/` root here (instead of making it the initial location)
  // mirrors that so `context.pop()` has somewhere to land, same as real
  // usage.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Future<String?> Function(String) onUserUtterance,
  }) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/handsfree'),
                child: const Text('start'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/handsfree',
          builder: (context, state) =>
              HandsFreeScreen(onUserUtterance: onUserUtterance),
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
          audioSinkProvider.overrideWithValue(sink),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
  }

  testWidgets(
    'no voice models installed shows the honest empty state, not a crash',
    (tester) async {
      // tmp is empty.
      await pumpScreen(tester, onUserUtterance: (t) async => 'reply');
      await tester.tap(find.text('start'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('Voice models needed'), findsOneWidget);
      expect(find.text('Set up voice'), findsOneWidget);

      await tester.tap(find.text('Set up voice'));
      await tester.pumpAndSettle();
      expect(find.text('models hub stand-in'), findsOneWidget);
    },
  );

  testWidgets('mic permission denied shows a clear message', (tester) async {
    installAllVoiceModels(tmp);
    mic.permissionGranted = false;
    await pumpScreen(tester, onUserUtterance: (t) async => 'reply');
    await tester.tap(find.text('start'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Microphone access needed'), findsOneWidget);
  });

  testWidgets(
    'a full turn walks Listening -> Speaking and shows both sides of the '
    'conversation',
    (tester) async {
      installAllVoiceModels(tmp);
      await pumpScreen(tester, onUserUtterance: (t) async => 'sure thing');
      await tester.tap(find.text('start'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('Listening…'), findsOneWidget);
      // UI-PARITY: the VoiceMock trust mark + turn-taking hint render on the
      // live conversation view (not the empty/permission views).
      expect(find.text('STT + TTS on-device'), findsOneWidget);
      expect(find.text('your turn — speak now'), findsOneWidget);

      mic.pushSpeech();
      mic.pushSilence();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('Speaking…'), findsOneWidget);
      expect(find.text('"hello there"'), findsOneWidget);
      expect(find.text('sure thing'), findsOneWidget);
      expect(find.text('End hands-free'), findsOneWidget);
    },
  );
}
