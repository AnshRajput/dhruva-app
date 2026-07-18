// D4: the OS download-notification config values + the AndroidManifest
// POST_NOTIFICATIONS permission. The `configureNotification` platform call
// itself is mobile-only (exercised on-device); these assert the config it
// applies and the manifest gate that lets it show on Android 13+.

import 'dart:io';

import 'package:dhruva/data/downloads/download_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final c = dhruvaDownloadNotificationConfig;

  test('running/complete/error notifications are configured', () {
    expect(c.running, isNotNull);
    expect(c.complete, isNotNull);
    expect(c.error, isNotNull);
  });

  test('running notification shows a live progress bar with tokens', () {
    expect(c.progressBar, isTrue);
    // background_downloader substitutes these tokens at runtime.
    expect(c.running!.title, contains('{filename}'));
    expect(c.running!.body, contains('{progress}'));
    // ETA/speed the human saw missing in the video ("--:-- left" only).
    expect(c.running!.body, contains('{networkSpeed}'));
    expect(c.running!.body, contains('{timeRemaining}'));
  });

  test('does not try to open the file on tap (GGUF is not user-openable)', () {
    expect(c.tapOpensFile, isFalse);
  });

  // QA: the diagnosis's exact wiring example names running/complete/error/
  // paused — `paused` wasn't asserted anywhere yet.
  test('paused notification is configured too', () {
    expect(c.paused, isNotNull);
  });

  // QA: `configureNotifications()` (background_downloader_backend.dart:
  // 24-40) is only ever invoked from `downloadManagerProvider`'s build
  // (core/di/providers.dart:135) — a Riverpod FutureProvider, cached for the
  // life of the container — so the "call once, before any enqueue" and
  // "request permission at most once" contract the diagnosis (§6) asks for
  // holds structurally: there is exactly one call site in lib/. Grep-based,
  // since the actual platform call can't run under `flutter test`.
  test('configureNotifications has exactly one call site (called once)', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('.configureNotifications()'),
        );
    expect(
      hits.length,
      1,
      reason:
          'configureNotifications() should be called from exactly one '
          'place (downloadManagerProvider) — more than one call site risks '
          'a duplicate permission-request prompt.',
    );
  });

  test('AndroidManifest declares POST_NOTIFICATIONS (Android 13+ gate)', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains('android.permission.POST_NOTIFICATIONS'),
      reason: 'without this, no download notification shows on Android 13+',
    );
  });
}
