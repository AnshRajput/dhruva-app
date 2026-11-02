/// The optional morning-brief notification (Settings > Notifications).
///
/// Privacy first: the notification text is a CONSTANT. It never carries an
/// event title, a name, a message or anything else from the user's data, so
/// nothing sensitive can show on the lock screen. Tapping it opens Today, where
/// the brief is written (in the foreground) from what is on the phone.
///
/// Scheduling: no network and no push. Local notifications are scheduled on
/// the phone with `flutter_local_notifications` (BSD-3, maintained). Because
/// the phone's time zone database is not shipped (it would add a second
/// dependency), each launch schedules the NEXT [scheduleDays] mornings as
/// one-shot alarms at absolute instants computed from the local clock, which
/// stays correct across daylight-saving changes; opening the app refreshes the
/// window. Android uses inexact alarms (no exact-alarm permission needed), so
/// the time can drift by a few minutes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../identity/app_identity.dart';

/// The ONLY text the notification ever shows.
const morningBriefBody = 'Your brief is ready to read';
const morningBriefTitle = AppIdentity.productName;

/// Payload that routes a tap to Today.
const morningBriefPayload = 'today';

/// Mornings kept scheduled ahead.
const scheduleDays = 7;

const _idBase = 7100;
const _channelId = 'morning_brief';

/// The next [days] local moments at [minutesAfterMidnight], starting with
/// today if that time is still ahead of [now], else tomorrow.
List<DateTime> nextBriefTimes(
  DateTime now,
  int minutesAfterMidnight, {
  int days = scheduleDays,
}) {
  final h = minutesAfterMidnight ~/ 60;
  final m = minutesAfterMidnight % 60;
  var first = DateTime(now.year, now.month, now.day, h, m);
  if (!first.isAfter(now)) {
    first = DateTime(now.year, now.month, now.day + 1, h, m);
  }
  return [
    for (var i = 0; i < days; i++)
      DateTime(first.year, first.month, first.day + i, h, m),
  ];
}

/// The slice of the OS notification API the scheduler needs, so tests can fake
/// it and assert exactly what would be shown.
abstract interface class NotificationGateway {
  /// Prepares the plugin; [onTap] gets the payload of a tapped notification.
  Future<void> init(void Function(String? payload) onTap);

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();

  /// Asks the OS for permission to post (Android 13+ POST_NOTIFICATIONS, iOS
  /// alert permission). True when granted.
  Future<bool> requestPermission();

  Future<bool> isPermitted();

  Future<void> cancelAll(Iterable<int> ids);

  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  });
}

class MorningBriefScheduler {
  MorningBriefScheduler(this._gateway, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final NotificationGateway _gateway;
  final DateTime Function() _clock;

  static final _ids = [for (var i = 0; i < scheduleDays; i++) _idBase + i];

  /// Turns the brief on: asks for permission and, when granted, schedules the
  /// next mornings. False when the OS said no (nothing is scheduled).
  Future<bool> enable(int minutesAfterMidnight) async {
    final ok = await _gateway.requestPermission();
    if (!ok) return false;
    await schedule(minutesAfterMidnight);
    return true;
  }

  /// (Re)schedules the next mornings; call on launch and when the time changes.
  Future<void> schedule(int minutesAfterMidnight) async {
    await _gateway.cancelAll(_ids);
    final times = nextBriefTimes(_clock(), minutesAfterMidnight);
    for (final (i, at) in times.indexed) {
      await _gateway.scheduleAt(
        id: _idBase + i,
        when: at,
        title: morningBriefTitle,
        body: morningBriefBody,
        payload: morningBriefPayload,
      );
    }
  }

  Future<void> disable() => _gateway.cancelAll(_ids);

  Future<bool> isPermitted() => _gateway.isPermitted();
}

/// The real thing, over `flutter_local_notifications`.
class PluginNotificationGateway implements NotificationGateway {
  PluginNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<void> init(void Function(String? payload) onTap) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        // The monochrome star the Quick Settings tile already ships.
        android: AndroidInitializationSettings('ic_tile_star'),
        // Permission is asked when the user turns the brief on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    _ready = true;
  }

  @override
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return (d?.didNotificationLaunchApp ?? false)
        ? d?.notificationResponse?.payload
        : null;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<bool> isPermitted() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final o = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return o?.isAlertEnabled ?? false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        false;
  }

  @override
  Future<void> cancelAll(Iterable<int> ids) async {
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      // An absolute instant: UTC avoids needing the local zone database.
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Morning brief',
          channelDescription: 'A daily nudge to read your brief.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      payload: payload,
    );
  }
}

final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => PluginNotificationGateway(),
);

final morningBriefSchedulerProvider = Provider<MorningBriefScheduler>(
  (ref) => MorningBriefScheduler(ref.watch(notificationGatewayProvider)),
);

/// Called once at startup: wires the tap to [navigate] (opens Today) and keeps
/// the scheduled window topped up while the brief is on. Never throws.
Future<void> startMorningBrief({
  required NotificationGateway gateway,
  required MorningBriefScheduler scheduler,
  required bool enabled,
  required int minutesAfterMidnight,
  required void Function() openToday,
}) async {
  try {
    await gateway.init((payload) {
      if (payload == morningBriefPayload) openToday();
    });
    if ((await gateway.launchPayload()) == morningBriefPayload) openToday();
    if (enabled && await scheduler.isPermitted()) {
      await scheduler.schedule(minutesAfterMidnight);
    }
  } on Object {
    // A notification problem must never block launch.
  }
}
