/// A persisted on/off preference over [PrefsStore] (stored as 'true' /
/// 'false'). One tiny class so each switch in Settings is a single provider
/// declaration instead of its own notifier.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs_store.dart';

class BoolPref extends AsyncNotifier<bool> {
  BoolPref(this.key, {required this.defaultValue});

  final String key;
  final bool defaultValue;

  @override
  Future<bool> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    return switch (await store.read(key)) {
      'true' => true,
      'false' => false,
      _ => defaultValue,
    };
  }

  Future<void> set(bool value) async {
    final store = await ref.read(prefsStoreProvider.future);
    state = AsyncData(value);
    await store.write(key, value.toString());
  }
}

/// Settings > Privacy: hide the app's content in the OS app switcher
/// (Android FLAG_SECURE, iOS cover view). Default OFF.
final hideInAppSwitcherProvider = AsyncNotifierProvider<BoolPref, bool>(
  () => BoolPref('hide_in_app_switcher', defaultValue: false),
);

/// Settings > Privacy: show the next calendar event's title on the home
/// widget. Default ON (it is the user's own calendar). The widget never shows
/// mail or notification content.
final widgetShowNextEventProvider = AsyncNotifierProvider<BoolPref, bool>(
  () => BoolPref('widget_show_next_event', defaultValue: true),
);

/// Settings > Notifications: the morning brief. Default OFF. Stored only;
/// the scheduler arrives with Today's brief (Wave 3), and the switch stays
/// hidden in the UI until it does.
final morningBriefEnabledProvider = AsyncNotifierProvider<BoolPref, bool>(
  () => BoolPref('morning_brief_enabled', defaultValue: false),
);

/// Settings > Notifications: OS notifications for model downloads. Default
/// ON (today's behaviour).
final downloadNotificationsProvider = AsyncNotifierProvider<BoolPref, bool>(
  () => BoolPref('download_notifications', defaultValue: true),
);

/// Settings > Notifications: when the morning brief should arrive, as minutes
/// after local midnight (default 07:30). Stored only until the scheduler
/// lands with Today's brief (Wave 3); no UI shows it yet.
class MorningBriefTimeNotifier extends AsyncNotifier<int> {
  static const key = 'morning_brief_minutes';
  static const defaultMinutes = 7 * 60 + 30;

  @override
  Future<int> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    final m = int.tryParse(await store.read(key) ?? '');
    return (m != null && m >= 0 && m < 24 * 60) ? m : defaultMinutes;
  }

  Future<void> set(int minutes) async {
    final store = await ref.read(prefsStoreProvider.future);
    final clamped = minutes.clamp(0, 24 * 60 - 1);
    state = AsyncData(clamped);
    await store.write(key, clamped.toString());
  }
}

final morningBriefMinutesProvider =
    AsyncNotifierProvider<MorningBriefTimeNotifier, int>(
      MorningBriefTimeNotifier.new,
    );
