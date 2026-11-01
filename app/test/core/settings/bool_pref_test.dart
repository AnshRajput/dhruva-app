// Persisted switches: defaults, persistence, and the morning-brief time.

import 'package:dhruva/core/settings/bool_pref.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(MemoryPrefsStore store) {
  final c = ProviderContainer(
    overrides: [prefsStoreProvider.overrideWith((ref) async => store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    'defaults: switcher off, widget title on, brief off, alerts on',
    () async {
      final c = _container(MemoryPrefsStore());
      expect(await c.read(hideInAppSwitcherProvider.future), isFalse);
      expect(await c.read(widgetShowNextEventProvider.future), isTrue);
      expect(await c.read(morningBriefEnabledProvider.future), isFalse);
      expect(await c.read(downloadNotificationsProvider.future), isTrue);
      expect(
        await c.read(morningBriefMinutesProvider.future),
        MorningBriefTimeNotifier.defaultMinutes,
      );
    },
  );

  test('values persist across containers', () async {
    final store = MemoryPrefsStore();
    final a = _container(store);
    await a.read(hideInAppSwitcherProvider.future);
    await a.read(hideInAppSwitcherProvider.notifier).set(true);
    await a.read(widgetShowNextEventProvider.future);
    await a.read(widgetShowNextEventProvider.notifier).set(false);
    await a.read(downloadNotificationsProvider.future);
    await a.read(downloadNotificationsProvider.notifier).set(false);
    await a.read(morningBriefMinutesProvider.future);
    await a.read(morningBriefMinutesProvider.notifier).set(8 * 60);

    final b = _container(store);
    expect(await b.read(hideInAppSwitcherProvider.future), isTrue);
    expect(await b.read(widgetShowNextEventProvider.future), isFalse);
    expect(await b.read(downloadNotificationsProvider.future), isFalse);
    expect(await b.read(morningBriefMinutesProvider.future), 8 * 60);
  });

  test('a garbage or out-of-range time falls back / clamps', () async {
    final c = _container(MemoryPrefsStore({'morning_brief_minutes': '99999'}));
    expect(
      await c.read(morningBriefMinutesProvider.future),
      MorningBriefTimeNotifier.defaultMinutes,
    );
    await c.read(morningBriefMinutesProvider.notifier).set(-5);
    expect(c.read(morningBriefMinutesProvider).value, 0);
  });
}
