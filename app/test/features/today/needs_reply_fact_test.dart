// Today's brief says how many messages need a reply (the Inbox's own rule),
// first, linking to the Inbox, and never counts the phone's own plumbing or
// this app's own notifications.

import 'package:dhruva/core/identity/app_identity.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/features/today/state/brief_compose.dart';
import 'package:dhruva/features/today/state/brief_facts.dart';
import 'package:dhruva/features/today/state/today_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'today_fixtures.dart';

DayBrief _compose({
  int replies = 0,
  List<NotificationGroup> groups = const [],
}) => composeBrief(
  now: fixtureNow,
  todaysEvents: [designSync],
  notificationGroups: groups,
  calendarConnected: true,
  needsReplyCount: replies,
  use24: false,
);

NotificationGroup _group(String pkg, String app, int count) => notifGroup([
  for (var i = 0; i < count; i++)
    notification(
      200 + i + pkg.length,
      pkg,
      app,
      '$app alert',
      'Something happened $i',
      at(6, 10 + i),
    ),
]);

void main() {
  test('"N messages need a reply" is the first sentence, linking to Inbox', () {
    final b = _compose(replies: 3);
    expect(b.sentences.first.plain, '3 messages need a reply.');
    final fact = b.facts.firstWhere((f) => f.n == 1);
    expect(fact.text, '3 messages need a reply.');
    expect(fact.ref, 'inbox:');
  });

  test('one message reads in the singular; none adds no sentence', () {
    expect(
      _compose(replies: 1).sentences.first.plain,
      '1 message needs a reply.',
    );
    expect(
      _compose().sentences.map((s) => s.plain).join(' '),
      isNot(contains('reply.')),
    );
  });

  test('system and own-app packages never become notification facts', () {
    final noisy = [
      _group('android', 'Android System', 4),
      _group('com.android.shell', 'Shell', 4),
      _group('com.android.systemui', 'System UI', 4),
      _group(AppIdentity.androidPackage, 'Dhruva', 4),
      _group('com.swiggy', 'Swiggy', 3),
    ];
    final text = _compose(groups: noisy).facts.map((f) => f.text).join(' ');
    expect(text, contains('3 notifications from Swiggy'));
    for (final hidden in ['Android System', 'Shell', 'System UI', 'Dhruva']) {
      expect(text, isNot(contains(hidden)));
    }
    expect(withoutSystemApps(noisy).map((g) => g.package), ['com.swiggy']);
  });

  test('the reply count skips system packages and what was marked read', () {
    final ask = notification(
      1,
      'com.whatsapp',
      'WhatsApp',
      'Ravi Menon',
      'Can you send the deck?',
      at(8),
    );
    final system = notification(
      2,
      'com.android.shell',
      'Shell',
      'Ravi Menon',
      'Can you send the deck?',
      at(8),
    );
    final old = notification(
      3,
      'com.whatsapp',
      'WhatsApp',
      'Sana Rao',
      'Can you call me?',
      at(5),
    );
    expect(needsReplyCount([ask, system, old], {}, null), 2);
    expect(needsReplyCount([ask, system, old], {}, at(6)), 1);
  });
}
