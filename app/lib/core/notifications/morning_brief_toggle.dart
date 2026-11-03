/// Turning the morning brief on or off, shared by Settings > Notifications and
/// the last onboarding step so both run the same permission flow.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/bool_pref.dart';
import 'morning_brief.dart';

/// Sets the morning brief to [on]. Turning it on asks the OS for permission
/// and schedules the next mornings; the pref is saved only when the OS said
/// yes. Returns false when [on] was refused (nothing is scheduled, the pref
/// stays off); turning off always returns true.
Future<bool> setMorningBrief(WidgetRef ref, {required bool on}) async {
  final enabled = ref.read(morningBriefEnabledProvider.notifier);
  final scheduler = ref.read(morningBriefSchedulerProvider);
  if (!on) {
    await enabled.set(false);
    await scheduler.disable();
    return true;
  }
  final minutes = await ref.read(morningBriefMinutesProvider.future);
  bool granted;
  try {
    granted = await scheduler.enable(minutes);
  } on Object {
    granted = false;
  }
  if (granted) await enabled.set(true);
  return granted;
}
