/// What a tap on Today does: connect the calendar, prep for a meeting in Ask,
/// open a cited source, open the OS calendar. Plain functions over `context` /
/// `ref`, with the OS intent behind an overridable provider so widget tests
/// never launch anything.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_facts.dart';
import '../state/today_data.dart';
import 'today_sheets.dart';
import 'today_widgets.dart';

/// Opens the system calendar at a moment. Android: the calendar app's
/// `content://com.android.calendar/time/<ms>` view; iOS: `calshow:`
/// (seconds since 2001-01-01). No write access is involved.
Future<bool> openCalendarAt(
  DateTime at, {
  TargetPlatform? platform,
  Future<bool> Function(Uri)? launch,
}) async {
  final target = platform ?? defaultTargetPlatform;
  final uri = target == TargetPlatform.iOS
      ? Uri.parse('calshow:${at.millisecondsSinceEpoch ~/ 1000 - 978307200}')
      : Uri.parse(
          'content://com.android.calendar/time/${at.millisecondsSinceEpoch}',
        );
  try {
    return await (launch ?? launchUrl)(uri);
  } on Object {
    return false;
  }
}

final openCalendarProvider = Provider<Future<bool> Function(DateTime)>(
  (ref) =>
      (at) => openCalendarAt(at),
);

Future<void> openInCalendar(
  BuildContext context,
  WidgetRef ref,
  ConnectorItem event,
) async {
  final ok = await ref.read(openCalendarProvider)(
    event.startsAt ?? ref.read(todayClockProvider)(),
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't open your calendar app. Open it yourself to see this event.",
        ),
      ),
    );
  }
}

/// Asks the OS for calendar access (no sign-in) and reads the events. The
/// connector reports the outcome on its status stream, which the cards show.
Future<ConnectorStatus?> connectCalendar(WidgetRef ref) =>
    connectAndSync(ref, ConnectorIds.calendar);

Future<void> openCalendarSettings(WidgetRef ref) async {
  try {
    final hub = await ref.read(connectorHubProvider.future);
    await hub.calendar.openSystemSettings();
  } on Object {
    // Nothing more to do: the card keeps showing the fix in words.
  }
}

/// "Prep" for a meeting: Ask opens with the question typed for the user and
/// Calendar + Contacts + Files pinned. The event's own text stays out of the
/// prompt (it is untrusted); Ask quotes the event itself in the sources block.
void prepForEvent(BuildContext context, ConnectorItem event) {
  final when = event.startsAt == null
      ? 'next'
      : formatClock(context, event.startsAt!);
  final prompt =
      'Prep me for my $when meeting: who is attending, what do I know about '
      'them, and any related notes.';
  unawaited(
    context.push(
      '/chat/new?prompt=${Uri.encodeQueryComponent(prompt)}'
      '&sources=calendar,contacts,folder&event=${event.id}',
    ),
  );
}

/// Opens what a cited phrase or fact points at.
Future<void> openFact(
  BuildContext context,
  WidgetRef ref,
  BriefFact fact,
) async {
  final store = ref.read(connectorStoreProvider);
  final parts = fact.ref.split(':');
  final kind = parts.first;
  final key = parts.skip(1).join(':');
  if (kind == 'event') {
    final id = int.tryParse(key) ?? 0;
    if (id == 0) {
      unawaited(context.push('/day'));
      return;
    }
    final found = await store.itemsByIds([id]);
    if (!context.mounted) return;
    if (found.isEmpty) {
      _gone(context, 'That event is no longer on your calendar.');
    } else {
      unawaited(showEventSheet(context, found.first));
    }
    return;
  }
  if (kind == 'notif') {
    final groups = ref.read(notificationGroupsProvider).value ?? const [];
    final match = groups.where((g) => g.package == key);
    if (match.isEmpty) {
      _gone(context, 'Those notifications are no longer on this phone.');
    } else {
      unawaited(showNotificationSheet(context, match.first));
    }
  }
}

void _gone(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
