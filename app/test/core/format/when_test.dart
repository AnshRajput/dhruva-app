// The shared "when" labels (one implementation behind Inbox, the privacy ledger
// and chat).

import 'package:dhruva/core/format/when.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12);

  test('timeAgo', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 30)), now), 'just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5m ago');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), '3h ago');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now), '2d ago');
  });

  test('shortWhen: clock today, then Yesterday, weekday, date', () {
    String clock(DateTime d) =>
        '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    expect(shortWhen(DateTime(2026, 11, 2, 7, 30), now, clock), '7:30');
    expect(shortWhen(DateTime(2026, 11, 1, 20), now, clock), 'Yesterday');
    expect(shortWhen(DateTime(2026, 10, 30, 20), now, clock), 'Fri');
    expect(shortWhen(DateTime(2026, 10, 3, 20), now, clock), '3 Oct');
  });
}
