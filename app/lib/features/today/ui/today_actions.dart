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
) => openCalendarWithFeedback(
  context,
  ref,
  event.startsAt ?? ref.read(todayClockProvider)(),
  message:
      "Couldn't open your calendar app. Open it yourself to see this event.",
);

/// Opens the OS calendar at [at]; says so when it could not.
Future<void> openCalendarWithFeedback(
  BuildContext context,
  WidgetRef ref,
  DateTime at, {
  String message =
      "Couldn't open your calendar app. Open it yourself to see your day.",
}) async {
  var ok = false;
  try {
    ok = await ref.read(openCalendarProvider)(at);
  } on Object {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Re-reads every connector. Says so when that failed, instead of a silent
/// button.
Future<void> retryConnectorSync(BuildContext context, WidgetRef ref) async {
  try {
    final hub = await ref.read(connectorHubProvider.future);
    await hub.sync.refresh();
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't read your calendar just now. Try again soon."),
      ),
    );
  }
}

/// Asks the OS for calendar access (no sign-in) and reads the events. The
/// connector reports the outcome on its status stream, which the cards show.
Future<ConnectorStatus?> connectCalendar(WidgetRef ref) =>
    connectAndSync(ref, ConnectorIds.calendar);

/// "Prep" for a meeting: the rule-built prep card (`/prep/:id`), made from
/// what is on the phone with no model involved. The card's "Ask a follow-up"
/// is the one way into Ask (`/ask/new`).
void prepForEvent(BuildContext context, ConnectorItem event) {
  unawaited(context.push('/prep/${event.id}'));
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
  if (kind == 'todos') {
    // The Library is a tab of the shell: switch to it, never push it.
    context.go('/library');
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
