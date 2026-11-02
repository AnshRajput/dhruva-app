// Parity row 31: the launcher shortcuts are still declared in the manifest and
// each one's `route` extra is understood by IntentInbox (routing itself is
// pinned in intent_inbox_test.dart).

import 'dart:io';

import 'package:dhruva/core/intents/intent_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shortcuts.xml declares Today, Ask, New chat and Actions, all routed',
    () {
      final xml = File(
        'android/app/src/main/res/xml/shortcuts.xml',
      ).readAsStringSync();
      final routes = RegExp(
        r'android:name="route" android:value="(\w+)"',
      ).allMatches(xml).map((m) => m.group(1)!).toList();
      expect(routes, ['today', 'ask', 'new_chat', 'workflows']);
      for (final r in routes) {
        expect(IntentInbox.locationFor({'route': r}), isNotNull, reason: r);
      }
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:resource="@xml/shortcuts"'),
      );
    },
  );
}
