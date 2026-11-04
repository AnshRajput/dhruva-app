// Hostile-input regressions for the Gmail connector review (PR #46): one test
// per fix. Everything here is attacker controlled (a mail sender), a hung
// provider, or a malformed Google response.
import 'dart:async';
import 'dart:convert';

import 'package:dhruva/core/actions/action_prompt.dart';
import 'package:dhruva/core/router/route_trust.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/gmail_connector.dart';
import 'package:dhruva/data/connectors/gmail_system_source.dart';
import 'package:dhruva/data/connectors/otp_guard.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_connector_sources.dart';

final _now = DateTime.utc(2026, 11, 4, 8);

GmailMessage msg(
  String id, {
  String from = 'Ravi Kumar <ravi@example.com>',
  String subject = 'Budget',
  String text = 'Numbers attached.',
  Person? person,
}) => GmailMessage(
  id: id,
  from: person ?? parseFromHeader(from),
  subject: subject,
  text: text,
  date: _now.subtract(const Duration(hours: 2)),
  labels: const {'INBOX', 'UNREAD'},
);

GmailThread thread(String id, [GmailMessage? m]) =>
    GmailThread(id, [m ?? msg('m-$id')]);

Future<T> fast<T>(FutureOr<T> Function() body, {int maxMs = 100}) async {
  final sw = Stopwatch()..start();
  final r = await body();
  expect(sw.elapsedMilliseconds, lessThan(maxMs), reason: 'took too long');
  return r;
}

String b64(String s) => base64Url.encode(utf8.encode(s));

api.Message plainMessage(String data, {String? snippet}) => api.Message(
  id: 'm',
  internalDate: '${_now.millisecondsSinceEpoch}',
  snippet: snippet,
  payload: api.MessagePart(
    mimeType: 'text/plain',
    body: api.MessagePartBody(data: data),
  ),
);

void main() {
  late AppDatabase db;
  late FakeGmailSource gmail;
  late ConnectorTestKit kit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    gmail = FakeGmailSource();
    kit = ConnectorTestKit.create(db, clock: () => _now, gmail: gmail);
  });
  tearDown(() async {
    await kit.dispose();
    await db.close();
  });

  GmailConnector conn() => kit.hub.gmail;
  Future<List<ConnectorItem>> mail() =>
      kit.hub.store.itemsOf(ConnectorIds.mail, kind: ItemKind.mail);
  Future<void> connected() async => expect(await conn().connect(), isTrue);

  // ---- B1 ---------------------------------------------------------------
  group('B1: the From header is parsed in linear time', () {
    test('a 100 KB hostile header is fast and the result is capped', () async {
      for (final raw in [
        'A${' ' * 100000}B <a@b.c>',
        'x' * 100000,
        '<' * 100000,
        '${'"' * 100000} <a@b.c>',
        '${' ' * 100000}a@b.c',
        '${'<a@' * 30000}>',
      ]) {
        final p = await fast(() => parseFromHeader(raw));
        expect((p?.name ?? '').length, lessThanOrEqualTo(maxMailNameChars));
        expect((p?.email ?? '').length, lessThanOrEqualTo(maxMailEmailChars));
      }
    });
  });

  // ---- B2 ---------------------------------------------------------------
  group('B2: everything read from Google is bounded before use', () {
    test('a 20 MB body costs one 16 KB base64 slice', () async {
      final big = 'A' * 20 * 1000 * 1000;
      final m = await fast(
        () => gmailMessageFromApi(plainMessage(big)),
        maxMs: 200,
      );
      expect(m.text.length, lessThanOrEqualTo(maxItemBodyChars));
      expect(m.text, isNotEmpty);
    });

    test('invalid base64 falls back to the snippet, entities decoded', () {
      final m = gmailMessageFromApi(
        plainMessage(
          '!!!not*base64???',
          snippet: 'Tom &amp; Jerry&#39;s &lt;3',
        ),
      );
      expect(m.text, "Tom & Jerry's <3");
      expect(decodeBodyData('@@@@'), isNull);
    });

    test('invalid UTF-8 is tolerated, not thrown', () {
      final data = base64Url.encode([0xff, 0xfe, 0x41, 0xc3]);
      expect(decodeBodyData(data), contains('A'));
    });

    test('a body cut mid-group still decodes (4-char boundary)', () {
      final s = decodeBodyData('QUJD' * 10000)!; // "ABC" repeated, 40k chars
      expect(s.length, 12288);
      expect(s, startsWith('ABCABC'));
    });

    test('5000-deep MIME nesting gives up instead of recursing', () {
      var part = api.MessagePart(
        mimeType: 'text/plain',
        body: api.MessagePartBody(data: b64('deep secret')),
      );
      for (var i = 0; i < 5000; i++) {
        part = api.MessagePart(mimeType: 'multipart/mixed', parts: [part]);
      }
      expect(plainTextOf(part), isNull);
      // A sane depth still works.
      var ok = api.MessagePart(
        mimeType: 'text/plain',
        body: api.MessagePartBody(data: b64('hello')),
      );
      for (var i = 0; i < 3; i++) {
        ok = api.MessagePart(mimeType: 'multipart/mixed', parts: [ok]);
      }
      expect(plainTextOf(ok), 'hello');
    });

    test('10000 sibling parts stop at the part budget', () {
      final root = api.MessagePart(
        mimeType: 'multipart/mixed',
        parts: [
          for (var i = 0; i < 10000; i++) api.MessagePart(mimeType: 'x/y'),
          api.MessagePart(
            mimeType: 'text/plain',
            body: api.MessagePartBody(data: b64('too far')),
          ),
        ],
      );
      expect(plainTextOf(root), isNull);
    });

    test('subject, sender name and email are capped before storage', () async {
      await connected();
      final huge = 'z' * 1000000;
      gmail.threads = [
        thread(
          't',
          msg(
            'm',
            subject: huge,
            person: Person(name: huge, email: huge),
          ),
        ),
      ];
      await conn().sync();
      final i = (await mail()).single;
      expect(i.title.length, maxMailSubjectChars);
      expect(i.people.single.name!.length, maxMailNameChars);
      expect(i.people.single.email!.length, maxMailEmailChars);
    });

    test('only the newest message of a thread is read in full, and one bad '
        'thread among good ones is skipped, not fatal', () async {
      final fullFetches = <String>[];
      final listPages = <String?>[];
      String json(Object o) => jsonEncode(o);
      final client = MockClient((req) async {
        final path = req.url.path;
        http.Response ok(Object o) => http.Response(
          json(o),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        if (path.endsWith('/threads')) {
          final page = req.url.queryParameters['pageToken'];
          listPages.add(page);
          return page == null
              ? ok({
                  'threads': [
                    {'id': 'a'},
                    {'id': 'bad'},
                  ],
                  'nextPageToken': 'p2',
                })
              : ok({
                  'threads': [
                    {'id': 'huge'},
                    {'id': 'c'},
                  ],
                });
        }
        if (path.contains('/threads/')) {
          final id = path.split('/').last;
          if (id == 'bad') return http.Response('boom', 500);
          final size = id == 'huge' ? 5 * 1024 * 1024 : 1000;
          return ok({
            'id': id,
            'messages': [
              {
                'id': '$id-old',
                'internalDate': '1000',
                'sizeEstimate': 10,
                'payload': {'headers': <Object>[]},
              },
              {
                'id': '$id-new',
                'internalDate': '2000',
                'sizeEstimate': size,
                'snippet': 'snip $id',
                'labelIds': ['INBOX'],
                'payload': {
                  'headers': [
                    {'name': 'From', 'value': 'Ravi <r@x.com>'},
                    {'name': 'Subject', 'value': 'S $id'},
                  ],
                },
              },
            ],
          });
        }
        if (path.contains('/messages/')) {
          final id = path.split('/').last;
          fullFetches.add(id);
          return ok({
            'id': id,
            'internalDate': '2000',
            'labelIds': ['INBOX'],
            'payload': {
              'mimeType': 'text/plain',
              'headers': [
                {'name': 'From', 'value': 'Ravi <r@x.com>'},
                {'name': 'Subject', 'value': 'S $id'},
              ],
              'body': {'data': b64('body of $id')},
            },
          });
        }
        return http.Response('?', 404);
      });
      final fetch = await readRecentThreads(
        api.GmailApi(client),
        since: _now.subtract(const Duration(days: 7)),
        maxThreads: 200,
      );
      expect([for (final t in fetch.threads) t.id], ['a', 'huge', 'c']);
      // The bad thread was skipped, so the listing is not "complete".
      expect(fetch.complete, isFalse);
      // Paged to the end.
      expect(listPages, [null, 'p2']);
      // Only the newest message, never the old one; the 5 MB one is not
      // downloaded at all, its snippet stands in.
      expect(fullFetches, unorderedEquals(['a-new', 'c-new']));
      final huge = fetch.threads.firstWhere((t) => t.id == 'huge');
      expect(huge.messages.single.text, 'snip huge');
      expect(huge.messageCount, 2);
      expect(fetch.threads.first.messages.single.text, 'body of a-new');
    });

    test(
      'a sign-in problem on a thread is not swallowed as "skipped"',
      () async {
        final client = MockClient((req) async {
          final json = {'content-type': 'application/json; charset=utf-8'};
          if (req.url.path.endsWith('/threads')) {
            return http.Response(
              jsonEncode({
                'threads': [
                  {'id': 'a'},
                ],
              }),
              200,
              headers: json,
            );
          }
          return http.Response(
            jsonEncode({
              'error': {'code': 401, 'message': 'bad token'},
            }),
            401,
            headers: json,
          );
        });
        await expectLater(
          readRecentThreads(api.GmailApi(client), since: _now, maxThreads: 10),
          throwsA(isA<api.DetailedApiRequestError>()),
        );
      },
    );
  });

  // ---- B3 ---------------------------------------------------------------
  group('B3: revoke always wins', () {
    test('a hung Gmail read cannot block the wipe', () async {
      await connected();
      gmail.threads = [thread('a')];
      await conn().sync();
      conn().revokeWaitFor = const Duration(milliseconds: 50);
      gmail.readGate = Completer<void>(); // never completes
      unawaited(conn().sync().then((_) {}, onError: (_) {}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await conn().revoke().timeout(const Duration(seconds: 5));
      expect(await mail(), isEmpty);
      expect(await kit.hub.store.account(ConnectorIds.mail), isNull);
      expect(conn().currentStatus.state, ConnectorState.notConnected);
    });

    test('the same bound protects another connector (BaseConnector)', () async {
      kit.calendar
        ..perm = DevicePermission.granted
        ..items = [calEvent('e1', start: DateTime.utc(2026, 11, 5, 9))];
      await kit.hub.calendar.connect();
      await kit.hub.calendar.sync();
      kit.hub.calendar.revokeWaitFor = const Duration(milliseconds: 50);
      kit.calendar.eventsGate = Completer<void>(); // hangs forever
      unawaited(kit.hub.calendar.sync().then((_) {}, onError: (_) {}));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await kit.hub.calendar.revoke().timeout(const Duration(seconds: 5));
      expect(await kit.hub.store.countItems('calendar'), 0);
      expect(await kit.hub.store.account('calendar'), isNull);
    });

    test(
      'a hung sign-out cannot block the wipe, and says it is unconfirmed',
      () async {
        await connected();
        gmail.threads = [thread('a')];
        await conn().sync();
        conn().revokeWaitFor = const Duration(milliseconds: 50);
        gmail.signOutGate = Completer<void>();
        await conn().revoke().timeout(const Duration(seconds: 5));
        expect(await mail(), isEmpty);
        expect(conn().remoteRevokeConfirmed, isFalse);
      },
    );

    test(
      'a refused remote revoke is reported, a confirmed one is too',
      () async {
        await connected();
        gmail.signOutConfirms = false;
        await conn().revoke();
        expect(conn().remoteRevokeConfirmed, isFalse);
        expect(
          GmailConnector.finishAtGoogle,
          contains('myaccount.google.com/permissions'),
        );
        await connected();
        gmail.signOutConfirms = true;
        await conn().revoke();
        expect(conn().remoteRevokeConfirmed, isTrue);
      },
    );

    test('a read that finishes after revoke started writes nothing', () async {
      await connected();
      gmail.threads = [thread('late')];
      final gate = gmail.readGate = Completer<void>();
      final sync = conn().sync().then((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final revoke = conn().revoke();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      await Future.wait([sync, revoke]);
      expect(await mail(), isEmpty);
      expect(await kit.hub.store.account(ConnectorIds.mail), isNull);
    });

    test(
      'the Gmail client refuses other hosts, plain http and redirects',
      () async {
        final seen = <http.BaseRequest>[];
        final inner = MockClient((req) async {
          seen.add(req);
          return http.Response('{}', 200);
        });
        final c = GmailBearerClient('tok', inner: inner);
        for (final bad in [
          'https://evil.example/gmail/v1/users/me/threads',
          'https://gmail.googleapis.com.evil.example/x',
          'http://gmail.googleapis.com/x',
          'https://oauth2.googleapis.com/revoke',
        ]) {
          await expectLater(
            c.get(Uri.parse(bad)),
            throwsA(isA<http.ClientException>()),
            reason: bad,
          );
        }
        expect(seen, isEmpty);
        await c.get(Uri.parse('https://gmail.googleapis.com/gmail/v1/x'));
        expect(seen.single.headers['Authorization'], 'Bearer tok');
        expect(seen.single.followRedirects, isFalse);
      },
    );
  });

  group('revoke race: an abandoned sync never touches a new connection', () {
    test(
      'revoke times out, user reconnects, the old read finishes late',
      () async {
        await connected();
        conn().revokeWaitFor = const Duration(milliseconds: 50);
        final gate1 = gmail.readGate = Completer<void>();
        final oldSync = conn().sync().then<Object?>(
          (r) => r,
          onError: (Object e) => e,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await conn().revoke(); // times out on the hung read, wipes anyway

        // Reconnect; the new connection starts its own read (held open).
        await connected();
        final gate2 = gmail.readGate = Completer<void>();
        final newSync = conn().sync();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(gmail.reads, 2, reason: 'a fresh flight, not joined to the old');

        // The old read finally returns, with the OLD account\'s mail.
        gmail.threads = [thread('old')];
        gate1.complete();
        await oldSync;
        expect(await mail(), isEmpty, reason: 'nothing of the old read stored');
        final ledger = await kit.hub.store.ledger(connector: ConnectorIds.mail);
        expect(ledger.where((e) => e.action == LedgerAction.read), isEmpty);

        // The new flight is intact: a call now joins it, no third read starts.
        final joined = conn().sync();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(gmail.reads, 2);
        gmail.threads = [thread('new')];
        gate2.complete();
        final a = await newSync;
        final b = await joined;
        expect(a.read, 1);
        expect(b.read, 1);
        expect([for (final i in await mail()) i.externalId], ['new']);
      },
    );
  });

  // ---- B4 ---------------------------------------------------------------
  group('B4: no external link can auto-send', () {
    test('text-to-send parameters are ignored on a link we did not build', () {
      final foreign = Uri.parse('/chat/new?prompt=hi&asys=evil&pkg=p&app=a');
      final forged = Uri.parse(
        '/chat/new?prompt=hi&asys=evil&$routeKeyParam=guess',
      );
      for (final u in [foreign, forged]) {
        for (final name in ['prompt', 'asys', 'pkg', 'app']) {
          expect(trustedParam(u, name), isNull, reason: '$u $name');
        }
      }
      final ours = Uri.parse(
        '/chat/new?prompt=hi&$routeKeyParam=$trustedRouteKey',
      );
      expect(trustedParam(ours, 'prompt'), 'hi');
    });
  });

  // ---- background ---------------------------------------------------------
  group('background sync without an Activity', () {
    test(
      'headless auth failure is a quiet skip, no ledger row, no card',
      () async {
        await connected();
        gmail.threads = [thread('a')];
        await conn().sync();
        final before = (await kit.hub.store.ledger(
          connector: ConnectorIds.mail,
        )).length;
        conn().headless = true;
        gmail.syncError = const GmailAuthException('no activity');
        final r = await conn().sync();
        expect(r.skipped, isNotNull);
        expect(conn().currentStatus.state, ConnectorState.connected);
        expect(
          (await kit.hub.store.ledger(connector: ConnectorIds.mail)).length,
          before,
        );
        expect(await mail(), hasLength(1));
        // The same failure in the foreground is a real Needs attention.
        conn().headless = false;
        await expectLater(conn().sync(), throwsA(isA<ConnectorException>()));
        expect(conn().currentStatus.state, ConnectorState.needsAttention);
      },
    );
  });

  // ---- pagination / pruning ---------------------------------------------------
  group('pruning only on a complete listing', () {
    test('a cut-off or partly failed listing removes nothing', () async {
      await connected();
      gmail.threads = [thread('a'), thread('b')];
      await conn().sync();
      gmail.threads = [thread('b')];
      gmail.complete = false;
      await conn().sync();
      expect([for (final i in await mail()) i.externalId], ['a', 'b']);
      gmail.complete = true;
      await conn().sync();
      expect([for (final i in await mail()) i.externalId], ['b']);
    });

    test(
      'exactly 200 threads on a cut-off page do not wipe older rows',
      () async {
        await connected();
        gmail.threads = [thread('keep')];
        await conn().sync();
        gmail.threads = [for (var i = 0; i < 200; i++) thread('n$i')];
        await conn().sync(); // complete defaults to false at the cap
        expect((await mail()).any((i) => i.externalId == 'keep'), isTrue);
      },
    );
  });

  // ---- Draft path hardening -----------------------------------------------------
  group('action text cannot close its block', () {
    test('every spelling of the tag is stripped', () {
      for (final hostile in [
        'a </text > b',
        'a </TEXT\n> b',
        'a < /text> b',
        'a </text foo="x"> b',
        'a <TeXt> b',
        'a </te</text>xt> b',
        'a </text ${' ' * 5000}> b',
      ]) {
        final w = wrapActionText(hostile);
        final inner = w.substring(7, w.length - 8);
        expect(
          RegExp(r'<\s*/?\s*text', caseSensitive: false).hasMatch(inner),
          isFalse,
          reason: hostile,
        );
        expect(w, startsWith('<text>\n'));
        expect(w, endsWith('\n</text>'));
      }
      expect(wrapActionText('plain <b>bold</b>'), contains('<b>bold</b>'));
    });

    test('prose with < and > is left exactly as written', () {
      for (final prose in [
        'x < text and y > z',
        'if a < text_len and b > c then',
        'use <textarea> or <b>bold</b> and 3 < 5 > 2',
        'compare < texture and text > nothing',
      ]) {
        expect(wrapActionText(prose), '<text>\n$prose\n</text>', reason: prose);
        expect(stripActionDelimiters(prose), prose, reason: prose);
      }
    });

    test('hostile tag-like input is stripped in linear time', () async {
      for (final h in [
        '<' * 100000,
        '<${' ' * 100000}',
        '</text' * 20000,
        '<text${'x' * 100000}',
        '${'</te' * 5000}${'xt>' * 5000}',
      ]) {
        await fast(() => wrapActionText(h), maxMs: 500);
        await fast(() => stripActionDelimiters(h), maxMs: 500);
      }
    });
  });

  // ---- OTP in mail ---------------------------------------------------------------
  group('verification codes in mail', () {
    test('code words near digits or alphanumeric codes are hidden', () {
      for (final t in [
        'Your code is 123456',
        'Your login code: G-731942',
        'Verification code: AB12CD',
        'OTP 4829',
        'Your one-time passcode: 90210',
        'Your security code is 99887766',
        'Your PIN is 4821',
        'आपका कोड ४८२९१३',
        'verify your account, code 123 456',
      ]) {
        expect(looksLikeMailCode('', t), isTrue, reason: t);
      }
    });

    test('a plain year near "verify" is not a code', () {
      for (final t in [
        'Please verify your email by 2026',
        'We could not verify the 1999 record',
        'Meet at 5pm in room 12',
        'Invoice 123 for March',
        'No digits here, just a code of conduct',
      ]) {
        expect(looksLikeMailCode('', t), isFalse, reason: t);
      }
    });

    test(
      'a code stays out of the store when mail says "Your code is 123456"',
      () async {
        await connected();
        gmail.threads = [
          thread(
            'o',
            msg('o', subject: 'Sign in', text: 'Your code is 123456.'),
          ),
        ];
        await conn().sync();
        final i = (await mail()).single;
        expect(i.body, hiddenCodeBody);
        expect(i.flags[otpFlag], isTrue);
        expect('${i.title}${i.body}', isNot(contains('123456')));
      },
    );

    test('an 8 KB wall of code words is checked in linear time', () async {
      await fast(
        () => looksLikeMailCode('', 'code ' * 1700 + 'verify ' * 1000),
        maxMs: 200,
      );
      await fast(() => looksLikeMailCode('', 'A1' * 4000), maxMs: 200);
    });
  });
}
