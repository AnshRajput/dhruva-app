// D15: "Open settings" for permission-denied states.

import 'dart:io';

import 'package:dhruva/core/intents/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/app-settings');
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

  test('Android asks the native side to open this app\'s settings', () async {
    mock((_) async => true);
    final ok = await openAppSettings(
      channel: channel,
      platform: TargetPlatform.android,
    );
    expect(ok, isTrue);
    expect(calls.single.method, 'openAppSettings');
  });

  test(
    'Android: a refusal or a missing native side is false, not a throw',
    () async {
      mock((_) async => false);
      expect(
        await openAppSettings(
          channel: channel,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      mock((_) async {
        throw PlatformException(code: 'boom');
      });
      expect(
        await openAppSettings(
          channel: channel,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        await openAppSettings(
          channel: channel,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    },
  );

  test(
    'iOS opens the app-settings: URL and never touches the channel',
    () async {
      mock((_) async => true);
      Uri? launched;
      final ok = await openAppSettings(
        channel: channel,
        platform: TargetPlatform.iOS,
        launch: (url) async {
          launched = url;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(launched.toString(), 'app-settings:');
      expect(calls, isEmpty);
    },
  );

  test('the native method exists and uses the standard app-details screen', () {
    final kotlin = File(
      'android/app/src/main/kotlin/tech/appuinside/dhruva/MainActivity.kt',
    ).readAsStringSync();
    expect(kotlin, contains('"openAppSettings"'));
    expect(kotlin, contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'));
    expect(kotlin, contains('Uri.fromParts("package", packageName, null)'));
  });
}
