import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/features/chat/state/message_info_x.dart';
import 'package:dhruva/features/chat/widgets/message_bubble.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final _redPng = File('test/assets/red_64.png').readAsBytesSync();

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

MessageInfo _message({
  required MessageRole role,
  required String content,
  String? reasoningContent,
  MessageStatus status = MessageStatus.complete,
}) {
  return MessageInfo(
    id: 1,
    conversationId: 1,
    role: role,
    content: content,
    reasoningContent: reasoningContent,
    status: status,
    createdAt: DateTime.now(),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  // `MessageBubble` renders a `TtsButton` (Loop 6, D2) on assistant bubbles
  // — `ProviderScope` + a `FakeAudioSink` override keep that off the real
  // `audioplayers` plugin channel in these widget tests.
  return tester.pumpWidget(
    ProviderScope(
      overrides: [audioSinkProvider.overrideWithValue(FakeAudioSink())],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  // The copy-button test exercises `Clipboard.setData`, which has no
  // built-in mock in `flutter_test` (it's a real engine channel call) —
  // stub it so the async gap resolves instead of throwing.
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

  testWidgets('user message renders its text', (tester) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(role: MessageRole.user, content: 'hello there'),
      ),
    );
    expect(find.textContaining('hello there'), findsOneWidget);
  });

  testWidgets('system message renders as a centered italic banner', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(role: MessageRole.system, content: 'Model changed'),
      ),
    );
    expect(find.text('Model changed'), findsOneWidget);
  });

  testWidgets(
    'assistant markdown renders bold text and a code block with copy',
    (tester) async {
      await _pump(
        tester,
        MessageBubble(
          message: _message(
            role: MessageRole.assistant,
            content: '**bold** text\n\n```dart\nprint(1);\n```',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('bold'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget); // language label
      expect(find.byIcon(Icons.copy), findsOneWidget);
      // DESIGNER BLOCKING #2: real tooltip/semantic label, not a bare
      // unlabeled InkWell.
      expect(find.byTooltip('Copy code'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byTooltip('Copied'), findsOneWidget);
      // Let the copy-icon's revert timer (motion.moderate, 300ms) run out so
      // no pending timer trips flutter_test's end-of-test invariant check.
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  group('N4 (staff review): markdown links', () {
    late _FakeUrlLauncher fakeLauncher;
    final realLauncher = UrlLauncherPlatform.instance;

    setUp(() {
      fakeLauncher = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = fakeLauncher;
    });

    tearDown(() {
      UrlLauncherPlatform.instance = realLauncher;
    });

    testWidgets('tapping a markdown link launches its href externally', (
      tester,
    ) async {
      await _pump(
        tester,
        MessageBubble(
          message: _message(
            role: MessageRole.assistant,
            content: '[the docs](https://example.com/docs)',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('the docs'));
      await tester.pumpAndSettle();

      expect(fakeLauncher.launched, ['https://example.com/docs']);
    });

    testWidgets('a non-http(s) href (trust-boundary case) is never launched', (
      tester,
    ) async {
      await _pump(
        tester,
        MessageBubble(
          message: _message(
            role: MessageRole.assistant,
            content: '[click me](javascript:alert(1))',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('click me'));
      await tester.pumpAndSettle();

      expect(fakeLauncher.launched, isEmpty);
    });
  });

  testWidgets('reasoning block is collapsed by default and expands on tap', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(
          role: MessageRole.assistant,
          content: 'the answer',
          reasoningContent: 'the scratch work',
        ),
        reasoningDurationMs: 4200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reasoning (4s)'), findsOneWidget);
    expect(find.text('the scratch work'), findsNothing);

    await tester.tap(find.text('Reasoning (4s)'));
    await tester.pumpAndSettle();

    expect(find.text('the scratch work'), findsOneWidget);
  });

  testWidgets('an actively streaming reasoning block reads "Reasoning…"', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _message(
          role: MessageRole.assistant,
          content: '',
          reasoningContent: 'still going',
        ),
        isStreaming: true,
        reasoningOpen: true,
      ),
    );

    expect(find.text('Reasoning…'), findsOneWidget);
  });

  testWidgets('regenerate/edit affordances fire their callbacks', (
    tester,
  ) async {
    var regenerated = false;
    var edited = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioSinkProvider.overrideWithValue(FakeAudioSink())],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(
                  message: _message(role: MessageRole.assistant, content: 'hi'),
                  onRegenerate: () => regenerated = true,
                ),
                MessageBubble(
                  message: _message(
                    role: MessageRole.user,
                    content: 'question',
                  ),
                  onEdit: () => edited = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // DESIGNER BLOCKING #2: both icons carry a real tooltip/semantic label
    // now, not a bare unlabeled InkWell.
    expect(find.byTooltip('Regenerate response'), findsOneWidget);
    expect(find.byTooltip('Edit message'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    expect(regenerated, isTrue);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edited, isTrue);
  });

  group('vision (Loop 7)', () {
    testWidgets(
      'D2: an attached image renders as a thumbnail, tap opens it full-size',
      (tester) async {
        await _pump(
          tester,
          MessageBubble(
            message: _message(role: MessageRole.user, content: 'what is this?'),
            attachedImage: _redPng,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);

        // Invoked directly rather than via `tester.tap` — the bubble's
        // `FractionallySizedBox`/`Align` scaffolding (built for a bounded
        // `ListView` item, not this isolated `SingleChildScrollView` host)
        // makes the thumbnail's true hit-test geometry unreliable in this
        // test harness; the callback itself is what's under test.
        tester
            .widget<GestureDetector>(
              find.byKey(const Key('attached-image-thumbnail')),
            )
            .onTap!();
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets(
      'D3: an extract-text result shows a copy-to-clipboard affordance',
      (tester) async {
        await _pump(
          tester,
          MessageBubble(
            message: _message(
              role: MessageRole.assistant,
              content: 'Hello World',
            ),
            isExtractResult: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Copy text'), findsOneWidget);

        await tester.tap(find.byTooltip('Copy text'));
        await tester.pump();
        await tester.pump();
        expect(find.byIcon(Icons.check), findsOneWidget);
        // Revert timer — drain it so no pending timer trips flutter_test's
        // end-of-test invariant check.
        await tester.pump(const Duration(milliseconds: 950));
      },
    );

    testWidgets(
      'a normal (non-extract) assistant reply has no copy affordance',
      (tester) async {
        await _pump(
          tester,
          MessageBubble(
            message: _message(role: MessageRole.assistant, content: 'hi'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Copy text'), findsNothing);
      },
    );
  });
}
