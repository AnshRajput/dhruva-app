// "Hide content in app switcher", Dart side: the channel call, tolerance of a
// missing native side, and that the channel name matches both native files.

import 'dart:io';

import 'package:dhruva/core/privacy/screen_privacy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel(ChannelScreenPrivacy.channelName),
      null,
    ),
  );

  test('setHidden forwards the flag on the privacy channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel(ChannelScreenPrivacy.channelName),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await const ChannelScreenPrivacy().setHidden(true);
    await const ChannelScreenPrivacy().setHidden(false);
    expect(calls.map((c) => c.method), everyElement('setHideInSwitcher'));
    expect(calls.map((c) => c.arguments), [true, false]);
  });

  test('a missing native handler is swallowed', () async {
    await const ChannelScreenPrivacy().setHidden(true); // no handler set
  });

  test('a platform error is swallowed', () async {
    messenger.setMockMethodCallHandler(
      const MethodChannel(ChannelScreenPrivacy.channelName),
      (call) async => throw PlatformException(code: 'x'),
    );
    await const ChannelScreenPrivacy().setHidden(true);
  });

  test('Android and iOS native sides use the same channel + method', () {
    final kotlin = File(
      'android/app/src/main/kotlin/tech/appuinside/dhruva/MainActivity.kt',
    ).readAsStringSync();
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    for (final src in [kotlin, swift]) {
      expect(src, contains(ChannelScreenPrivacy.channelName));
      expect(src, contains('setHideInSwitcher'));
    }
    expect(kotlin, contains('FLAG_SECURE'));
    expect(swift, contains('willDeactivateNotification'));
  });
}
