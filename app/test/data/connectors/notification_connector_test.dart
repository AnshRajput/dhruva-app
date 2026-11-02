import 'dart:convert';
import 'dart:io';

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/notification_connector.dart';
import 'package:dhruva/data/connectors/notification_queue.dart';
import 'package:dhruva/data/connectors/otp_guard.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_connector_sources.dart';

String line({
  String pkg = 'com.chat.app',
  String? app = 'Chat',
  String? title = 'Ravi',
  String? text = 'Lunch?',
  Object? t,
  Object? v = 1,
}) => jsonEncode({
  'v': v,
  'pkg': pkg,
  'app': app,
  'title': title,
  'text': text,
  't': t ?? DateTime.utc(2026, 11, 1, 7, 30).millisecondsSinceEpoch,
});

void main() {
  final now = DateTime.utc(2026, 11, 1, 8);

  group('looksLikeVerificationCode', () {
    test('hides wording plus a 4 to 8 digit code (English and Hindi)', () {
      for (final (t, b) in [
        ('Bank', 'Your OTP is 482913. Do not share it.'),
        ('', 'otp 1234'),
        ('Login', 'Use 5566 as your one-time password'),
        ('', 'Your one time passcode: 90210'),
        ('Verification code', '123-456'),
        ('Verify', 'Your security code is 99887766'),
        ('', '482913 is your Google verification code'),
        ('बैंक', 'आपका ओटीपी 482913 है'),
        ('', 'आपका कोड ४८२९१३ है'),
      ]) {
        expect(looksLikeVerificationCode(t, b), isTrue, reason: '$t / $b');
      }
    });

    test('hides a bare code from an app that commonly sends codes', () {
      for (final (t, b) in [
        ('AX-HDFCBK', 'G-731942'),
        ('', '731942'),
        ('Messages', '482913 is your code'),
        ('Messages', 'Code: 4829'),
        ('731942', ''), // the code sits in the title, text empty
        ('Messages', '123 456'),
      ]) {
        expect(
          looksLikeVerificationCode(
            t,
            b,
            pkg: 'com.google.android.apps.messaging',
          ),
          isTrue,
          reason: '$t / $b',
        );
      }
    });

    test('the bare-code rule is conservative: sender, and mostly a code', () {
      const sms = 'com.google.android.apps.messaging';
      // Same text from an app that is not a code sender: kept.
      expect(
        looksLikeVerificationCode('Ravi', 'G-731942', pkg: 'com.whatsapp'),
        isFalse,
      );
      expect(looksLikeVerificationCode('Ravi', 'G-731942'), isFalse);
      // A real message that happens to contain a number: kept.
      for (final b in [
        'Your order 123456 has been shipped and arrives on Tuesday',
        'Lunch at 1? Table for six is booked',
        'Call me back on 98765 43210 when you are free please',
        'Hello', // no code at all
      ]) {
        expect(
          looksLikeVerificationCode('Mum', b, pkg: sms),
          isFalse,
          reason: b,
        );
      }
    });

    test('keeps ordinary notifications', () {
      for (final (t, b) in [
        ('Ravi', 'Lunch at 1?'),
        ('Bank', 'Debited 500 at 12:30'),
        (
          'Delivery',
          'Order 123456789012 shipped',
        ), // long digit run, no wording
        ('', 'Your OTP will arrive shortly'), // wording, no code
        ('', 'Call 98765 43210 now'), // digits, no wording
        ('Cab', 'Ride verified'), // "verified" is not the code wording
      ]) {
        expect(looksLikeVerificationCode(t, b), isFalse, reason: '$t / $b');
      }
    });
  });

  group('parseQueueLine', () {
    test('accepts a well-formed line', () {
      final n = parseQueueLine(line(), now: now)!;
      expect(n.pkg, 'com.chat.app');
      expect(n.app, 'Chat');
      expect(n.title, 'Ravi');
      expect(n.text, 'Lunch?');
      expect(n.time, DateTime.utc(2026, 11, 1, 7, 30));
    });

    test('rejects corrupt and structurally wrong lines', () {
      for (final bad in [
        '',
        'not json',
        '{"v":1,',
        '[]',
        '"str"',
        'null',
        '{}',
        line(v: 2),
        line(v: '1'),
        line(pkg: 'nodots'),
        line(pkg: '../../etc/passwd'),
        line(pkg: 'com.x y'),
        line(t: 'yesterday'),
        line(t: 1.5),
        line(t: 0),
        line(t: now.add(const Duration(days: 30)).millisecondsSinceEpoch),
        line(title: '', text: ''),
        line(title: null, text: null),
        jsonEncode({'v': 1, 'pkg': 'com.x.y', 'title': 5, 't': 1760000000000}),
      ]) {
        expect(parseQueueLine(bad, now: now), isNull, reason: bad);
      }
    });

    test('a line over the length cap is dropped unparsed', () {
      final huge = line(text: 'x' * maxQueueLineChars);
      expect(parseQueueLine(huge, now: now), isNull);
    });

    test('control characters are stripped and long text is capped', () {
      final n = parseQueueLine(
        line(
          title: 'Hi\u0000\u0007 there\u001b',
          text: 'a' * (maxNotificationTextChars + 500),
        ),
        now: now,
      )!;
      expect(n.title, 'Hi there');
      expect(n.text.length, maxNotificationTextChars);
    });

    test('missing app name falls back to the package id', () {
      expect(parseQueueLine(line(app: null), now: now)!.app, 'com.chat.app');
    });

    test('excluded packages are dropped', () {
      expect(
        parseQueueLine(line(), now: now, excluded: {'com.chat.app'}),
        isNull,
      );
    });

    test('dedupe id is stable and differs by content', () {
      final a = parseQueueLine(line(), now: now)!;
      final b = parseQueueLine(line(), now: now)!;
      final c = parseQueueLine(line(text: 'Dinner?'), now: now)!;
      expect(a.dedupeId, b.dedupeId);
      expect(a.dedupeId, isNot(c.dedupeId));
    });
  });

  group('NotificationQueue.drain', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dhruva_queue'));
    tearDown(() => dir.deleteSync(recursive: true));

    File live() => File(p.join(dir.path, NotificationQueue.liveName));

    test('missing directory or file is just empty', () async {
      final none = await NotificationQueue(
        Directory(p.join(dir.path, 'nope')),
      ).drain(now: now);
      expect(none.notifications, isEmpty);
      final empty = await NotificationQueue(dir).drain(now: now);
      expect(empty.notifications, isEmpty);
    });

    test(
      'corrupt lines are skipped, good ones survive, counts are right',
      () async {
        live().writeAsStringSync(
          [
            line(text: 'one'),
            'garbage{{{',
            '',
            line(text: 'two'),
            '{"v":1}',
            line(text: 'three'),
          ].join('\n'),
        );
        final batch = await NotificationQueue(dir).drain(now: now);
        expect(batch.notifications.map((n) => n.text), ['one', 'two', 'three']);
        expect(batch.skipped, 2);
      },
    );

    test('invalid UTF-8 does not crash the drain', () async {
      live().writeAsBytesSync([
        ...utf8.encode('${line(text: 'ok')}\n'),
        0xff,
        0xfe,
        0x0a,
        ...utf8.encode(line(text: 'after')),
      ]);
      final batch = await NotificationQueue(dir).drain(now: now);
      expect(batch.notifications.map((n) => n.text), contains('after'));
    });

    test(
      'reads the rotated file before the live one; commit deletes both',
      () async {
        File(
          p.join(dir.path, NotificationQueue.oldName),
        ).writeAsStringSync('${line(text: 'older')}\n');
        live().writeAsStringSync('${line(text: 'newer')}\n');
        final batch = await NotificationQueue(dir).drain(now: now);
        expect(batch.notifications.map((n) => n.text), ['older', 'newer']);
        expect(live().existsSync(), isFalse);
        await batch.commit();
        expect(dir.listSync(), isEmpty);
      },
    );

    test('an uncommitted drain is re-read next time (crash safety)', () async {
      live().writeAsStringSync('${line(text: 'keep me')}\n');
      final first = await NotificationQueue(dir).drain(now: now);
      expect(first.notifications, hasLength(1));
      // No commit: the app died before storing.
      final second = await NotificationQueue(dir).drain(now: now);
      expect(second.notifications.map((n) => n.text), ['keep me']);
      await second.commit();
      expect(dir.listSync(), isEmpty);
    });

    test('a new live file started during a drain is not lost', () async {
      live().writeAsStringSync('${line(text: 'a')}\n');
      final batch = await NotificationQueue(dir).drain(now: now);
      // The listener appends to a fresh live file right after the rename.
      live().writeAsStringSync('${line(text: 'b')}\n');
      await batch.commit();
      final next = await NotificationQueue(dir).drain(now: now);
      expect(next.notifications.map((n) => n.text), ['b']);
    });

    test('total bytes read per drain are capped', () async {
      final big = StringBuffer();
      final one = '${line(text: 'y' * 1000)}\n';
      for (var i = 0; i < (maxQueueBytesPerDrain ~/ one.length) * 2; i++) {
        big.write(one);
      }
      live().writeAsStringSync(big.toString());
      final batch = await NotificationQueue(dir).drain(now: now);
      final cap = maxQueueBytesPerDrain ~/ one.length;
      expect(batch.notifications.length, lessThanOrEqualTo(cap + 1));
      expect(batch.notifications.length, greaterThan(cap ~/ 2));
      await batch.commit();
      expect(dir.listSync(), isEmpty); // the overflow is dropped, not kept
    });
  });

  group('NotificationConnector', () {
    late AppDatabase db;
    late ConnectorTestKit kit;
    var clock = DateTime.utc(2026, 11, 1, 8);

    setUp(() {
      clock = DateTime.utc(2026, 11, 1, 8);
      db = AppDatabase(NativeDatabase.memory());
      kit = ConnectorTestKit.create(db, clock: () => clock);
    });
    tearDown(() async {
      await kit.dispose();
      await db.close();
    });

    File live() => File(p.join(kit.queueDir.path, NotificationQueue.liveName));

    test('iOS: unsupported, UI hides it, connect/sync do nothing', () async {
      final ios = ConnectorTestKit.create(db, notificationsSupported: false);
      await ios.hub.notifications.refreshStatus();
      expect(
        ios.hub.notifications.currentStatus.state,
        ConnectorState.unsupported,
      );
      await ios.hub.notifications.connect();
      expect(ios.notifications.capture, isFalse);
      expect(await ios.hub.store.account('notifications'), isNull);
      await ios.dispose();
    });

    test('off by default: nothing captured, status not connected', () async {
      await kit.hub.notifications.refreshStatus();
      expect(
        kit.hub.notifications.currentStatus.state,
        ConnectorState.notConnected,
      );
      expect(kit.notifications.capture, isFalse);
    });

    test('connect without OS access: arms capture, opens the settings page, '
        'asks the user to switch it on', () async {
      await kit.hub.notifications.connect();
      expect(kit.notifications.capture, isTrue);
      expect(kit.notifications.settingsOpened, 1);
      expect(kit.notifications.excluded, contains(ownApplicationId));
      final s = kit.hub.notifications.currentStatus;
      expect(s.state, ConnectorState.needsAttention);
      expect(s.detail, contains('Open settings'));

      // The user flips the switch; the next status check sees it.
      kit.notifications.granted = true;
      await kit.hub.notifications.refreshStatus();
      expect(
        kit.hub.notifications.currentStatus.state,
        ConnectorState.connected,
      );
    });

    test('first time: "one more step"; after access was on and is switched '
        'off: "turned off" (different copy)', () async {
      await kit.hub.notifications.connect();
      final pending = kit.hub.notifications.currentStatus.detail!;
      expect(pending, contains('One more step'));

      kit.notifications.granted = true;
      await kit.hub.notifications.refreshStatus();
      kit.notifications.granted = false;
      await kit.hub.notifications.refreshStatus();
      final revoked = kit.hub.notifications.currentStatus.detail!;
      expect(revoked, contains('was turned off'));
      expect(revoked, contains('Open settings'));
      expect(revoked, isNot(pending));
    });

    test(
      'status follows the OS grant (granted -> revoked in settings)',
      () async {
        kit.notifications.granted = true;
        await kit.hub.notifications.connect();
        expect(kit.notifications.settingsOpened, 0);
        expect(
          kit.hub.notifications.currentStatus.state,
          ConnectorState.connected,
        );
        kit.notifications.granted = false;
        await kit.hub.notifications.refreshStatus();
        expect(
          kit.hub.notifications.currentStatus.state,
          ConnectorState.needsAttention,
        );
      },
    );

    test('ingests the queue, dedupes a repeated line, prunes old ones, '
        'writes the ledger', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      live().writeAsStringSync(
        [
          line(text: 'Lunch?'),
          line(text: 'Lunch?'), // rotation can repeat a line
          line(pkg: 'com.bank.app', app: 'Bank', title: 'Debit', text: '₹500'),
          line(
            text: 'ancient',
            t: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
          ),
        ].join('\n'),
      );
      final r = await kit.hub.notifications.sync();
      expect(r.read, 4);
      final items = await kit.hub.store.itemsOf('notifications');
      // 2 distinct recent + the ancient one pruned (older than 7 days).
      expect(items.map((i) => i.body), unorderedEquals(['Lunch?', '₹500']));
      expect(items.first.flags['pkg'], isNotNull);
      final ledger = await kit.hub.store.ledger(connector: 'notifications');
      expect(ledger.firstWhere((e) => e.action == LedgerAction.read).count, 4);
      expect(kit.queueDir.listSync(), isEmpty);
    });

    test('user-excluded apps and this app are never stored', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      await kit.hub.notifications.setExcludedApps(['com.bank.app']);
      expect(
        kit.notifications.excluded,
        containsAll([ownApplicationId, 'com.bank.app']),
      );
      live().writeAsStringSync(
        [
          line(pkg: 'com.bank.app', text: 'secret'),
          line(pkg: ownApplicationId, text: 'mine'),
          line(text: 'fine'),
        ].join('\n'),
      );
      await kit.hub.notifications.sync();
      expect(
        (await kit.hub.store.itemsOf('notifications')).map((i) => i.body),
        ['fine'],
      );
    });

    test('captured history is still read after access is switched off, and '
        'the card says what to do', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      kit.notifications.granted = false;
      live().writeAsStringSync('${line(text: 'late')}\n');
      await kit.hub.notifications.sync();
      expect(await kit.hub.store.countItems('notifications'), 1);
      expect(
        kit.hub.notifications.currentStatus.state,
        ConnectorState.needsAttention,
      );
    });

    test('verification codes are redacted before storing; the rest is kept '
        'as is', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      live().writeAsStringSync(
        [
          line(
            pkg: 'com.bank.app',
            app: 'Bank',
            title: 'Bank',
            text: 'Your OTP is 482913. Do not share it.',
          ),
          line(text: 'Lunch at 1?'),
          line(
            pkg: 'com.shop.app',
            app: 'Shop',
            title: '771204 is your code',
            text: 'Use this verification code to sign in.',
          ),
        ].join('\n'),
      );
      await kit.hub.notifications.sync();
      final items = await kit.hub.store.itemsOf('notifications');
      expect(items.map((i) => i.body), [
        hiddenCodeBody,
        'Lunch at 1?',
        hiddenCodeBody,
      ]);
      for (final i in items) {
        expect('${i.title} ${i.body}', isNot(contains('482913')));
        expect('${i.title} ${i.body}', isNot(contains('771204')));
      }
      final hidden = items.where((i) => i.flags[otpFlag] == true);
      expect(hidden.map((i) => i.title), unorderedEquals(['Bank', 'Shop']));
      expect(
        items.where((i) => i.body == 'Lunch at 1?').single.flags[otpFlag],
        isNull,
      );
      // Nor can the code be searched for.
      final index = await kit.hub.store.itemsOf('notifications');
      expect(index.any((i) => i.body.contains('482913')), isFalse);
    });

    test('a bare code from an SMS app is redacted before storing', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      live().writeAsStringSync(
        [
          line(
            pkg: 'com.google.android.apps.messaging',
            app: 'Messages',
            title: 'AX-HDFCBK',
            text: 'G-731942',
          ),
        ].join('\n'),
      );
      await kit.hub.notifications.sync();
      final item = (await kit.hub.store.itemsOf('notifications')).single;
      expect(item.body, hiddenCodeBody);
      expect(item.flags[otpFlag], isTrue);
      expect('${item.title} ${item.body}', isNot(contains('731942')));
    });

    test('each drain writes its own ledger row with its own count; empty '
        'drains between them write none', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      live().writeAsStringSync(
        [line(text: 'one'), line(text: 'two'), line(text: 'three')].join('\n'),
      );
      await kit.hub.notifications.sync();
      await kit.hub.notifications.sync(); // nothing queued
      live().writeAsStringSync(
        [line(text: 'four'), line(text: 'five')].join('\n'),
      );
      await kit.hub.notifications.sync();
      final reads = (await kit.hub.store.ledger(
        connector: 'notifications',
      )).where((e) => e.action == LedgerAction.read);
      expect(reads.map((e) => e.count), [2, 3]); // newest first
    });

    test('an empty drain leaves no "Read 0" ledger row but still counts as '
        'a sync', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      await kit.hub.notifications.sync();
      final ledger = await kit.hub.store.ledger(connector: 'notifications');
      expect(ledger.map((e) => e.action), [LedgerAction.connect]);
      expect(
        (await kit.hub.store.account('notifications'))!.lastSyncAt,
        isNotNull,
      );
    });

    test('an unreachable queue directory is a needs-attention card', () async {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      kit.notifications.failQueueDir = true;
      await expectLater(
        kit.hub.notifications.sync(),
        throwsA(isA<ConnectorException>()),
      );
      expect(
        kit.hub.notifications.currentStatus.state,
        ConnectorState.needsAttention,
      );
    });

    test(
      'revoke: capture off, stored items AND queued files deleted',
      () async {
        kit.notifications.granted = true;
        await kit.hub.notifications.connect();
        live().writeAsStringSync('${line(text: 'one')}\n');
        await kit.hub.notifications.sync();
        live().writeAsStringSync('${line(text: 'queued, not yet ingested')}\n');
        File(
          p.join(kit.queueDir.path, NotificationQueue.oldName),
        ).writeAsStringSync('${line(text: 'older queued')}\n');

        await kit.hub.notifications.revoke();

        expect(kit.notifications.capture, isFalse);
        expect(await kit.hub.store.countItems('notifications'), 0);
        expect(kit.queueDir.listSync(), isEmpty);
        expect(
          (await kit.hub.store.ledger(
            connector: 'notifications',
          )).map((e) => e.action),
          [LedgerAction.revoke],
        );
        expect(
          kit.hub.notifications.currentStatus.state,
          ConnectorState.notConnected,
        );
        await kit.hub.notifications.openSystemSettings();
        expect(kit.notifications.settingsOpened, greaterThan(0));
      },
    );
  });
}
