// Fixtures shared by the Today tests: calendar events and notifications as the
// connectors store them.

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';

/// 2026-11-02 07:42, the time on the comps.
final fixtureNow = DateTime(2026, 11, 2, 7, 42);

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 2, h, m);

ConnectorItem event(
  int id,
  String title,
  DateTime start,
  DateTime end, {
  List<Person> people = const [],
  String? location,
  bool allDay = false,
  String body = '',
}) => ConnectorItem(
  id: id,
  source: ConnectorIds.calendar,
  externalId: 'e$id',
  kind: ItemKind.event,
  title: title,
  body: body,
  people: people,
  startsAt: start,
  sentAt: null,
  flags: {
    'end': end.millisecondsSinceEpoch,
    'allDay': allDay,
    if (location != null) 'location': location,
  },
  summary: null,
  summaryModel: null,
  updatedAt: start,
);

ConnectorItem notification(
  int id,
  String pkg,
  String app,
  String title,
  String text,
  DateTime sentAt,
) => ConnectorItem(
  id: id,
  source: ConnectorIds.notifications,
  externalId: 'n$id',
  kind: ItemKind.notification,
  title: title,
  body: text,
  people: const [],
  startsAt: null,
  sentAt: sentAt,
  flags: {'pkg': pkg, 'app': app},
  summary: null,
  summaryModel: null,
  updatedAt: sentAt,
);

ConnectorItem contact(int id, String name, String email, {String? photo}) =>
    ConnectorItem(
      id: id,
      source: ConnectorIds.contacts,
      externalId: 'c$id',
      kind: ItemKind.contact,
      title: name,
      body: '',
      people: [Person(name: name, email: email)],
      startsAt: null,
      sentAt: null,
      flags: {if (photo != null) 'photo': photo},
      summary: null,
      summaryModel: null,
      updatedAt: fixtureNow,
    );

NotificationGroup notifGroup(List<ConnectorItem> items) {
  final first = items.first;
  return NotificationGroup(
    package: first.flags['pkg']! as String,
    appLabel: first.flags['app']! as String,
    items: items,
  );
}

/// The day on the comps: Design sync 9:30, Budget review 11:00, a WhatsApp from
/// Ravi, and seven Swiggy/HDFC pings.
final designSync = event(
  1,
  'Design sync',
  at(9, 30),
  at(10, 15),
  people: const [
    Person(name: 'Ravi', email: 'ravi@x.test'),
    Person(email: 'sana@x.test'),
    Person(email: 'dev@x.test'),
  ],
  location: 'Google Meet',
  body: 'Location: Google Meet\nAgenda: icons',
);
final budgetReview = event(2, 'Budget review', at(11), at(12), location: 'Room 4B');
final raviMessage = notification(
  10,
  'com.whatsapp',
  'WhatsApp',
  'Ravi Menon',
  'Wants your OK on the 18.4L marketing line before the 11:00 review.',
  at(7, 12),
);
final swiggyPings = [
  for (var i = 0; i < 4; i++)
    notification(20 + i, 'in.swiggy', 'Swiggy', 'Swiggy', 'Offer $i', at(6, 10 + i)),
];
final hdfcPings = [
  for (var i = 0; i < 3; i++)
    notification(30 + i, 'com.hdfc', 'HDFC', 'HDFC Bank', 'Alert $i', at(5, 10 + i)),
];
