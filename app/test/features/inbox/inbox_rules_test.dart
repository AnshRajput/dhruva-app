// Inbox rules: meta-narrating summaries are rejected, the sender (not the app)
// names the row, and messages from people asking something rise to Needs reply.

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/features/inbox/state/inbox_grouping.dart';
import 'package:dhruva/features/inbox/state/inbox_rules.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectorItem _n(
  int id, {
  String title = 'Ravi Menon',
  String body = '',
  String app = 'WhatsApp',
  String? summary,
  bool read = false,
  DateTime? at,
}) => ConnectorItem(
  id: id,
  source: 'notifications',
  externalId: 'n$id',
  kind: ItemKind.notification,
  title: title,
  body: body,
  people: const [],
  startsAt: null,
  sentAt: at ?? DateTime(2026, 11, 2, 9),
  flags: {'pkg': 'com.$app', 'app': app, if (read) 'read': true},
  summary: summary,
  summaryModel: null,
  updatedAt: at ?? DateTime(2026, 11, 2, 9),
);

void main() {
  group('isMetaSummary', () {
    test('rejects text that narrates the notification', () {
      for (final s in [
        'The text is a notification from a phone about a design sync.',
        'The notification is about a design sync',
        'This notification says your order shipped',
        "Market data from the user's phone, including prices",
        'The notification from HDFC Bank indicates a debit',
        'A message from Amma about dinner',
        'Here is a one-line summary: Ravi wants approval',
        'Sure! Ravi wants approval',
        'Summary: Ravi wants approval',
        "The user's phone received a message",
        '"The text is about lunch"',
        'ok',
      ]) {
        expect(isMetaSummary(s), isTrue, reason: s);
      }
    });

    test('keeps summaries that say what the message is about', () {
      for (final s in [
        'Ravi needs your OK on the 18.4L marketing line before 11:00.',
        'Amma asks what you want for dinner.',
        'Your order ships tomorrow.',
        'Design sync moved to 3:30.',
        'Theme review is due Friday',
      ]) {
        expect(isMetaSummary(s), isFalse, reason: s);
      }
    });

    test('a meta summary falls back to the first line of the body', () {
      final item = _n(
        1,
        body: '\n  Can you approve the budget?\nThanks',
        summary: 'The text is a notification from a phone',
      );
      expect(usableSummary(item), isNull);
      expect(rowLineOf(item), 'Can you approve the budget?');
      expect(
        rowLineOf(_n(2, body: 'x', summary: 'Ravi wants a yes before noon.')),
        'Ravi wants a yes before noon.',
      );
    });
  });

  group('sender', () {
    test('the notification title names the row, the app only when it must', () {
      expect(senderOf(_n(1, title: 'Ravi Menon')), 'Ravi Menon');
      expect(hasPersonSender(_n(1, title: 'Ravi Menon')), isTrue);
      expect(senderOf(_n(2, title: 'Shell', app: 'Shell')), 'Shell');
      expect(hasPersonSender(_n(2, title: 'shell', app: 'Shell')), isFalse);
      expect(senderOf(_n(3, title: '  ', app: 'Slack')), 'Slack');
    });
  });

  group('needsReply', () {
    test('a person asking a question or making a request', () {
      expect(needsReply(_n(1, body: 'Are you free at 3?')), isTrue);
      expect(needsReply(_n(2, body: 'Please approve the budget')), isTrue);
      expect(needsReply(_n(3, body: 'let me know about dinner')), isTrue);
    });

    test('not for statements, bulk text, read items or apps', () {
      expect(needsReply(_n(1, body: 'Reached home.')), isFalse);
      expect(
        needsReply(_n(2, body: 'Rs 500 debited. Not you? Call us')),
        isFalse,
        reason: 'a bank alert is addressed to everyone',
      );
      expect(needsReply(_n(3, body: 'Can you call?', read: true)), isFalse);
      expect(
        needsReply(_n(4, title: 'Shell', app: 'Shell', body: 'Can you call?')),
        isFalse,
        reason: 'the app posting it is not a person',
      );
      expect(
        needsReply(_n(5, title: 'HDFC BANK 123', body: 'Please pay')),
        isFalse,
        reason: 'digits in a sender are not a name',
      );
    });

    test('a known contact counts even with a one-word title', () {
      final item = _n(1, title: 'amma', body: 'dinner?');
      expect(needsReply(item), isFalse); // lower-case title is no name
      expect(needsReply(item, knownContacts: {'amma'}), isTrue);
    });

    test('groupInbox puts Needs reply first and leaves the rest in place', () {
      final now = DateTime(2026, 11, 2, 12);
      final items = [
        _n(1, body: 'Reached home.'),
        _n(2, body: 'Can you review this?', at: DateTime(2026, 11, 2, 8)),
        _n(3, body: 'Old note', at: DateTime(2026, 10, 30)),
      ];
      final s = groupInbox(items, now, needsReplyIds: needsReplyIds(items));
      expect(s.map((x) => x.title), [needsReplyTitle, 'Today', 'Earlier']);
      expect(s.first.items.map((i) => i.id), [2]);
      expect(s[1].items.map((i) => i.id), [1]);
    });
  });
}
