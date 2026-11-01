// Cold-start launcher shortcuts / widget / tile: the Android intent carries a
// `route` extra, which FlutterActivity would also read as the ENGINE initial
// route ("/new_chat" -> Page Not Found). MainActivity must pin it to "/", and
// IntentInbox then routes the extra from the first frame.

import 'dart:io';

import 'package:dhruva/core/intents/intent_inbox.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/main.dart' show navigateFromIntent;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

void main() {
  test('MainActivity pins the engine initial route to "/"', () {
    final src = File(
      'android/app/src/main/kotlin/tech/appuinside/dhruva/MainActivity.kt',
    ).readAsStringSync();
    expect(src, contains('override fun getInitialRoute(): String = "/"'));
  });

  for (final c in const [
    ('new_chat', '/chat/new'),
    ('talk', '/chat/new'),
    ('workflows', '/actions'),
  ]) {
    testWidgets('cold start with route=${c.$1} lands cleanly', (tester) async {
      // Engine boots at "/" (-> Today), then the initial intent arrives.
      await pumpDhruvaApp(tester, location: '/');
      const channel = MethodChannel('test/cold-start');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => {'route': c.$1});
      await IntentInbox(navigate: navigateFromIntent, channel: channel).start();
      await tester.pumpAndSettle();

      expect(find.textContaining('Page Not Found'), findsNothing);
      expect(
        appRouter.routerDelegate.currentConfiguration.last.matchedLocation,
        c.$2,
      );
    });
  }
}
