// H3: "Ask Dhruva AI" (PROCESS_TEXT) must not boot a second Flutter engine /
// app in the same process. These read the Android sources: the activity is a
// UI-less trampoline, the replacement result still round-trips, and the
// exported activities pin their Dart entrypoint.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = 'android/app/src/main/kotlin/tech/appuinside/dhruva/';
  final trampoline = File('${dir}ProcessTextActivity.kt').readAsStringSync();
  final main = File('${dir}MainActivity.kt').readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  String code(String s) => s
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//.*'), '');

  test('ProcessTextActivity is a plain Activity, not a Flutter host', () {
    final src = code(trampoline);
    expect(src, contains('class ProcessTextActivity : Activity()'));
    expect(src, isNot(contains('FlutterActivity')));
    expect(src, isNot(contains('MainActivity()'))); // not a subclass
    expect(src, isNot(contains('FlutterEngine')));
    expect(src, isNot(contains('FlutterView')));
  });

  test('MainActivity is the only Flutter host and is not subclassed', () {
    final src = code(main);
    expect(src, contains('class MainActivity : FlutterActivity()'));
    expect(src, isNot(contains('open class MainActivity')));
    expect(RegExp(r':\s*MainActivity\(\)').hasMatch(src), isFalse);
    expect(src, contains('getDartEntrypointFunctionName(): String = "main"'));
  });

  test('the trampoline forwards the text and gets out of the way', () {
    final src = code(trampoline);
    expect(src, contains('Intent(this, MainActivity::class.java)'));
    expect(src, contains('Intent.EXTRA_PROCESS_TEXT'));
    // A read-only selection has nothing to wait for.
    expect(src, contains('if (token == null) finish()'));
    // Back in the source app without replacing: step aside, don't eat taps.
    expect(src, contains('if (leftOnce) finish()'));
  });

  test('"Replace selected text" still round-trips through the bridge', () {
    final t = code(trampoline);
    final m = code(main);
    // The trampoline (in the calling app's task) sets the result...
    expect(t, contains('activity.setResult('));
    expect(t, contains('Activity.RESULT_OK'));
    expect(t, contains('activity.finish()'));
    // ...when Dart asks MainActivity to return text, and only then.
    expect(m, contains('"setProcessTextResult" -> returnProcessText'));
    expect(m, contains('ProcessTextBridge.deliver(text)'));
    expect(m, contains('MAX_RESULT_CHARS'));
    // Replaceable needs the trampoline's one-time token (the activity is
    // exported: a bare extra from any app is not trusted).
    expect(m, contains('ProcessTextBridge.accepts('));
    expect(t, contains('SecureRandom'));
    expect(t, contains('callingActivity != null'));
    expect(t, contains('EXTRA_PROCESS_TEXT_READONLY'));
  });

  test('manifest: the trampoline has no Flutter embedding metadata', () {
    final block = RegExp(
      r'<activity\b[^>]*\.ProcessTextActivity[^>]*>.*?</activity>',
      dotAll: true,
    ).firstMatch(manifest)!.group(0)!;
    expect(block, contains('android:launchMode="standard"'));
    expect(block, contains('TrampolineTheme'));
    expect(block, isNot(contains('flutter')));
    expect(block, contains('android.intent.action.PROCESS_TEXT'));
  });
}
