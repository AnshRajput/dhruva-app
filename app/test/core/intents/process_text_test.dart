// PROCESS_TEXT round trip (Android): Dart bridge, inbox flag, and the platform
// files that make the native side work.

import 'dart:io';

import 'package:dhruva/core/intents/intent_inbox.dart';
import 'package:dhruva/core/intents/process_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/process-text');
  final calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ProcessTextBridge', () {
    test('validate rejects blank and oversized text, accepts the rest', () {
      expect(ProcessTextBridge.validate('   '), ProcessTextFailure.empty);
      expect(ProcessTextBridge.validate(''), ProcessTextFailure.empty);
      expect(
        ProcessTextBridge.validate('x' * (processTextMaxResultChars + 1)),
        ProcessTextFailure.tooLong,
      );
      expect(
        ProcessTextBridge.validate('x' * processTextMaxResultChars),
        isNull,
      );
      expect(ProcessTextBridge.validate('Hello'), isNull);
    });

    test('sends the trimmed reply over setProcessTextResult', () async {
      mock((_) async => true);
      final failure = await ProcessTextBridge(
        channel: channel,
      ).returnResult('  Polished text.  ');
      expect(failure, isNull);
      expect(calls.single.method, 'setProcessTextResult');
      expect(calls.single.arguments, 'Polished text.');
    });

    test('never calls native for invalid input', () async {
      mock((_) async => true);
      final b = ProcessTextBridge(channel: channel);
      expect(await b.returnResult(' '), ProcessTextFailure.empty);
      expect(
        await b.returnResult('x' * (processTextMaxResultChars + 1)),
        ProcessTextFailure.tooLong,
      );
      expect(calls, isEmpty);
    });

    test('maps native refusals to failures', () async {
      mock((_) async {
        throw PlatformException(code: 'not_replaceable');
      });
      expect(
        await ProcessTextBridge(channel: channel).returnResult('hi'),
        ProcessTextFailure.notReplaceable,
      );
      mock((_) async {
        throw PlatformException(code: 'too_long');
      });
      expect(
        await ProcessTextBridge(channel: channel).returnResult('hi'),
        ProcessTextFailure.tooLong,
      );
    });

    test('no native side (iOS, tests): not replaceable, no crash', () async {
      // No mock handler registered for this channel.
      expect(
        await ProcessTextBridge(channel: channel).returnResult('hi'),
        ProcessTextFailure.notReplaceable,
      );
    });

    test('every failure has plain-language copy', () {
      for (final f in ProcessTextFailure.values) {
        expect(processTextFailureMessage(f), isNotEmpty);
      }
    });
  });

  group('IntentInbox replaceable flag', () {
    test('only text with replaceable:true counts', () {
      expect(
        IntentInbox.isReplaceable({'text': 'hi', 'replaceable': true}),
        isTrue,
      );
      expect(
        IntentInbox.isReplaceable({'text': 'hi', 'replaceable': false}),
        isFalse,
      );
      expect(IntentInbox.isReplaceable({'text': 'hi'}), isFalse);
      expect(
        IntentInbox.isReplaceable({'text': '  ', 'replaceable': true}),
        isFalse,
      );
      // A string "true" from a hostile/odd sender is not a bool true.
      expect(
        IntentInbox.isReplaceable({'text': 'hi', 'replaceable': 'true'}),
        isFalse,
      );
      expect(IntentInbox.isReplaceable(null), isFalse);
    });

    test('handle reports replaceable and still navigates', () {
      final seen = <String>[];
      final flags = <bool>[];
      final inbox = IntentInbox(navigate: seen.add, onReplaceable: flags.add);
      inbox.handle({'text': 'fix this', 'replaceable': true});
      inbox.handle({'text': 'read only text', 'replaceable': false});
      inbox.handle({'text': 'shared'});
      inbox.handle({'route': 'ask'});
      inbox.handle({'junk': 1}); // nothing actionable: no callback, no nav
      expect(flags, [true, false, false, false]);
      expect(seen, hasLength(4));
      expect(seen.first, startsWith('/actions?text='));
    });

    test('the session provider follows the flag', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(processTextSessionProvider), isFalse);
      c.read(processTextSessionProvider.notifier).set(true);
      expect(c.read(processTextSessionProvider), isTrue);
    });
  });

  group('platform files', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/tech/appuinside/dhruva/MainActivity.kt',
    ).readAsStringSync();

    test('PROCESS_TEXT targets a standard-launch-mode activity', () {
      final activity = RegExp(
        r'<activity\s+android:name="\.ProcessTextActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(activity, contains('android.intent.action.PROCESS_TEXT'));
      expect(activity, contains('android:launchMode="standard"'));
      expect(activity, contains('android:exported="true"'));
      // MainActivity stays singleTask, which cannot return results, and no
      // longer carries the PROCESS_TEXT filter.
      final main = RegExp(
        r'<activity\s+android:name="\.MainActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(main, contains('android:launchMode="singleTask"'));
      expect(main, isNot(contains('PROCESS_TEXT')));
      expect(manifest, isNot(contains('ProcessTextAlias')));
    });

    test('native side validates before handing a result back', () {
      expect(kotlin, contains('open class MainActivity'));
      expect(kotlin, contains('class ProcessTextActivity : MainActivity()'));
      // Editable only: the READONLY extra must be present and false, and the
      // launch must have a calling activity (started for a result).
      expect(kotlin, contains('EXTRA_PROCESS_TEXT_READONLY'));
      expect(kotlin, contains('callingActivity != null'));
      expect(
        kotlin,
        contains(
          'setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT',
        ),
      );
      // Input size validation + the same cap as Dart.
      expect(kotlin, contains('MAX_RESULT_CHARS = 100_000'));
      expect(processTextMaxResultChars, 100000);
      expect(kotlin, contains('text.length > MAX_RESULT_CHARS'));
      expect(kotlin, contains('text.isNullOrBlank()'));
    });
  });
}
