// Rule-built prep: who is in the meeting, what the phone knows about them and
// which notifications are from them. No model is involved anywhere.

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/features/today/state/prep_data.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectorItem _item(
  int id,
  ItemKind kind, {
  String title = '',
  String body = '',
  List<Person> people = const [],
  Map<String, Object?> flags = const {},
  DateTime? at,
}) => ConnectorItem(
  id: id,
  source: 'x',
  externalId: 'e$id',
  kind: kind,
  title: title,
  body: body,
  people: people,
  startsAt: kind == ItemKind.event ? at : null,
  sentAt: kind == ItemKind.notification ? at : null,
  flags: flags,
  summary: null,
  summaryModel: null,
  updatedAt: at ?? DateTime(2026, 11, 2),
);

void main() {
  final ravi = const Person(name: 'Ravi', email: 'ravi@x.test');
  final sana = const Person(name: 'Sana', email: 'sana@x.test');

  test(
    'people: contact names win, duplicates collapse, shared meetings show',
    () {
      final event = _item(1, ItemKind.event, people: [ravi, sana, ravi]);
      final other = _item(
        2,
        ItemKind.event,
        title: 'Budget review',
        people: [ravi],
      );
      final contact = _item(
        9,
        ItemKind.contact,
        title: 'Ravi Menon',
        flags: {'photo': 'abc'},
      );
      final out = prepPeople(event, {'ravi@x.test': contact}, [event, other]);
      expect(out.map((p) => p.name), ['Ravi Menon', 'Sana']);
      expect(out.first.inContacts, isTrue);
      expect(out.first.photoBase64, 'abc');
      expect(out.first.otherMeetings.map((e) => e.id), [2]);
      expect(out.last.inContacts, isFalse);
      expect(out.last.otherMeetings, isEmpty);
    },
  );

  test('notifications: from the person or naming them, newest first', () {
    final n = [
      _item(
        1,
        ItemKind.notification,
        title: 'Ravi Menon',
        body: 'ok',
        at: DateTime(2026, 11, 2, 8),
      ),
      _item(
        2,
        ItemKind.notification,
        title: 'Amma',
        body: 'Ask Ravi Menon about it',
        at: DateTime(2026, 11, 2, 9),
      ),
      _item(3, ItemKind.notification, title: 'Swiggy', body: 'Order placed'),
      _item(
        4,
        ItemKind.notification,
        title: 'Ravi',
        body: 'see you',
        at: DateTime(2026, 11, 1),
      ),
    ];
    final out = notificationsAbout(['Ravi Menon'], n);
    expect(out.map((i) => i.id), [2, 1, 4]);
    expect(notificationsAbout(['Ra'], n), isEmpty, reason: 'too short');
    expect(notificationsAbout(['Ravi Menon'], n, limit: 1), hasLength(1));
  });

  test('queries: the title then up to three people', () {
    final e = _item(1, ItemKind.event, title: 'Design sync');
    final people = [
      for (final n in ['A1', 'B2', 'C3', 'D4']) PrepPerson(name: n),
    ];
    expect(prepQueries(e, people), ['Design sync', 'A1', 'B2', 'C3']);
  });
}
