/// Appearance settings: theme mode (System / Light / Dark) and the
/// "reduce transparency" switch for the iOS glass-chrome approximation. Both
/// persist through [PrefsStore]; both default to following the system.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/prefs_store.dart';

const _themeModeKey = 'theme_mode';
const _reduceTransparencyKey = 'reduce_transparency';

ThemeMode parseThemeMode(String? raw) => switch (raw) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    return parseThemeMode(await store.read(_themeModeKey));
  }

  Future<void> set(ThemeMode mode) async {
    final store = await ref.read(prefsStoreProvider.future);
    state = AsyncData(mode);
    await store.write(_themeModeKey, mode.name);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// App-level "reduce transparency". Flutter exposes no iOS "Reduce
/// Transparency" flag, so [useGlassChrome] also honours
/// `MediaQuery.highContrast` (iOS "Increase Contrast"); this switch is the
/// explicit user override.
class ReduceTransparencyNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    return (await store.read(_reduceTransparencyKey)) == 'true';
  }

  Future<void> set(bool value) async {
    final store = await ref.read(prefsStoreProvider.future);
    state = AsyncData(value);
    await store.write(_reduceTransparencyKey, value.toString());
  }
}

final reduceTransparencyProvider =
    AsyncNotifierProvider<ReduceTransparencyNotifier, bool>(
      ReduceTransparencyNotifier.new,
    );
