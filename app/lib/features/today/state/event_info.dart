/// Small readings of a calendar event for the Up next card and detail sheet.
library;

import '../../../data/connectors/connector.dart';

const _meetingHosts = <(String, String)>[
  ('meet.google.com', 'Google Meet'),
  ('zoom.us', 'Zoom'),
  ('teams.microsoft.com', 'Microsoft Teams'),
  ('teams.live.com', 'Microsoft Teams'),
  ('webex.com', 'Webex'),
];

/// "Google Meet" and friends when the event carries a video-call link in its
/// location or notes, else null. The link itself is never opened from here.
String? meetingLabel(ConnectorItem e) {
  final loc = e.flags['location'];
  final hay = '${loc is String ? loc : ''}\n${e.body}'.toLowerCase();
  for (final (host, label) in _meetingHosts) {
    if (hay.contains(host)) return label;
  }
  return null;
}

/// Where the event is, as one short line: the meeting app, or the room.
String? placeLabel(ConnectorItem e) {
  final meeting = meetingLabel(e);
  if (meeting != null) return meeting;
  final loc = e.flags['location'];
  if (loc is! String) return null;
  final t = loc.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t.startsWith('http')) return null;
  return t.length > 40 ? '${t.substring(0, 39).trimRight()}…' : t;
}

/// The event's notes without the "Location: ..." line the connector prepends.
String eventNotes(ConnectorItem e) {
  final lines = e.body.split('\n');
  if (lines.isNotEmpty && lines.first.startsWith('Location: ')) {
    lines.removeAt(0);
  }
  return lines.join('\n').trim();
}
