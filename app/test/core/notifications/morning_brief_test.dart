// The morning-brief notification: when it is scheduled, that its text is a
// constant that can never carry the user's data, and the permission paths.

import 'package:dhruva/core/identity/app_identity.dart';
import 'package:dhruva/core/notifications/morning_brief.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_notification_gateway.dart';

void main() {
  final now = DateTime(2026, 11, 2, 7, 42);
  const sevenThirty = 7 * 60 + 30;

  group('nextBriefTimes', () {
    test('a time already passed today starts tomorrow', () {
      final t = nextBriefTimes(now, sevenThirty);
      expect(t.first, DateTime(2026, 11, 3, 7, 30));
      expect(t.length, scheduleDays);
      expect(t.last, DateTime(2026, 11, 9, 7, 30));
    });

    test('a time still ahead today starts today', () {
      final t = nextBriefTimes(now, 8 * 60);
      expect(t.first, DateTime(2026, 11, 2, 8));
    });

    test('exactly now counts as passed', () {
      expect(
        nextBriefTimes(now, 7 * 60 + 42).first,
        DateTime(2026, 11, 3, 7, 42),
      );
    });

    test('rolls over months', () {
      final t = nextBriefTimes(DateTime(2026, 11, 29, 23), 6 * 60);
      expect(t.map((d) => d.day), [30, 1, 2, 3, 4, 5, 6]);
    });
  });

  group('MorningBriefScheduler', () {
    test(
      'enable asks for permission then schedules the next mornings',
      () async {
        final g = FakeGateway();
        final ok = await MorningBriefScheduler(
          g,
          clock: () => now,
        ).enable(sevenThirty);
        expect(ok, isTrue);
        expect(g.permissionRequests, 1);
        expect(g.scheduled.length, scheduleDays);
        expect(g.scheduled.first.when, DateTime(2026, 11, 3, 7, 30));
        expect({for (final s in g.scheduled) s.id}.length, scheduleDays);
      },
    );

    test('permission refused: nothing is scheduled', () async {
      final g = FakeGateway(permitted: false);
      final ok = await MorningBriefScheduler(
        g,
        clock: () => now,
      ).enable(sevenThirty);
      expect(ok, isFalse);
      expect(g.scheduled, isEmpty);
    });

    test(
      'rescheduling clears the old ones first; disable clears them',
      () async {
        final g = FakeGateway();
        final s = MorningBriefScheduler(g, clock: () => now);
        await s.schedule(sevenThirty);
        expect(g.cancelled, isNotEmpty);
        g.cancelled.clear();
        await s.disable();
        expect(g.cancelled.length, scheduleDays);
      },
    );

    test(
      'the notification text is generic and never carries user content',
      () async {
        final g = FakeGateway();
        await MorningBriefScheduler(g, clock: () => now).enable(sevenThirty);
        for (final s in g.scheduled) {
          expect(s.title, AppIdentity.productName);
          expect(s.body, 'Your brief is ready to read');
          expect(s.payload, 'today');
        }
        // The text is fixed at compile time: it has no digits (times, counts),
        // so nothing from the calendar or messages can be in it.
        expect(RegExp(r'\d').hasMatch(morningBriefBody), isFalse);
        expect(RegExp(r'\d').hasMatch(morningBriefTitle), isFalse);
      },
    );
  });

  group('startMorningBrief', () {
    test(
      'tapping the notification opens Today; other payloads do not',
      () async {
        final g = FakeGateway();
        var opened = 0;
        await startMorningBrief(
          gateway: g,
          scheduler: MorningBriefScheduler(g, clock: () => now),
          enabled: false,
          minutesAfterMidnight: sevenThirty,
          openToday: () => opened++,
        );
        g.tap!('today');
        g.tap!('something-else');
        g.tap!(null);
        expect(opened, 1);
      },
    );

    test('a notification that launched the app opens Today', () async {
      final g = FakeGateway()..launch = 'today';
      var opened = 0;
      await startMorningBrief(
        gateway: g,
        scheduler: MorningBriefScheduler(g, clock: () => now),
        enabled: false,
        minutesAfterMidnight: sevenThirty,
        openToday: () => opened++,
      );
      expect(opened, 1);
    });

    test('on and permitted: tops up the next mornings at launch', () async {
      final g = FakeGateway();
      await startMorningBrief(
        gateway: g,
        scheduler: MorningBriefScheduler(g, clock: () => now),
        enabled: true,
        minutesAfterMidnight: sevenThirty,
        openToday: () {},
      );
      expect(g.scheduled.length, scheduleDays);
    });

    test('off, or permission since revoked: schedules nothing', () async {
      final off = FakeGateway();
      await startMorningBrief(
        gateway: off,
        scheduler: MorningBriefScheduler(off, clock: () => now),
        enabled: false,
        minutesAfterMidnight: sevenThirty,
        openToday: () {},
      );
      expect(off.scheduled, isEmpty);
      final revoked = FakeGateway(permitted: false);
      await startMorningBrief(
        gateway: revoked,
        scheduler: MorningBriefScheduler(revoked, clock: () => now),
        enabled: true,
        minutesAfterMidnight: sevenThirty,
        openToday: () {},
      );
      expect(revoked.scheduled, isEmpty);
    });
  });
}
