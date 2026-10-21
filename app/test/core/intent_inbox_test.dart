import 'package:dhruva/core/intents/intent_inbox.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared text routes to workflows with encoded text', () {
    expect(
      IntentInbox.locationFor({'text': ' hello & bye '}),
      '/workflows?text=hello+%26+bye',
    );
  });

  test('shortcut routes', () {
    expect(IntentInbox.locationFor({'route': 'new_chat'}), '/chat/new');
    expect(IntentInbox.locationFor({'route': 'workflows'}), '/workflows');
  });

  test('text wins over route; blank and unknown are ignored', () {
    expect(
      IntentInbox.locationFor({'text': 'x', 'route': 'new_chat'}),
      startsWith('/workflows?text='),
    );
    expect(IntentInbox.locationFor({'text': '  '}), isNull);
    expect(IntentInbox.locationFor({'route': 'nope'}), isNull);
    expect(IntentInbox.locationFor(null), isNull);
  });

  test('start handles initial intent and later pushes', () async {
    const channel = MethodChannel('test/intents');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'route': 'workflows'},
        );
    final seen = <String>[];
    await IntentInbox(navigate: seen.add, channel: channel).start();
    expect(seen, ['/workflows']);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'test/intents',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onIntent', {'text': 'hey'}),
          ),
          (_) {},
        );
    expect(seen.last, '/workflows?text=hey');
  });

  test('missing native channel is tolerated', () async {
    final seen = <String>[];
    await IntentInbox(
      navigate: seen.add,
      channel: const MethodChannel('test/absent'),
    ).start();
    expect(seen, isEmpty);
  });
}
