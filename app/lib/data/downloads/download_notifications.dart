/// OS-notification config for downloads (UX-hardening Phase B, D4). Kept
/// separate from the backend adapter so the exact copy + progress-bar flag
/// are pure data a `flutter test` can assert (the `configureNotification`
/// platform call itself is mobile-only and exercised on-device).
///
/// `background_downloader` owns the task lifecycle and substitutes
/// `{filename}`, `{progress}`, `{networkSpeed}`, `{timeRemaining}` tokens
/// itself and drives the Android progress bar — so this is a config object,
/// not a second notification pipeline. Applies globally (GGUF + voice
/// downloads alike). `{networkSpeed}`/`{timeRemaining}` render as '--' / '--:--'
/// until the plugin has a real estimate, so the copy stays honest.
library;

import 'package:background_downloader/background_downloader.dart' as bg;

/// The global download-notification config. Progress bar on (Android);
/// `tapOpensFile` off — GGUF/voice bundles aren't user-openable files.
///
/// [finishAlerts] (Settings > Notifications): when false the complete / error
/// / paused notifications are dropped. The RUNNING notification stays either
/// way: Android requires one for the foreground service that keeps model
/// downloads alive while the app is in the background.
bg.TaskNotificationConfig downloadNotificationConfig({
  bool finishAlerts = true,
}) => bg.TaskNotificationConfig(
  running: const bg.TaskNotification(
    '{filename}',
    'Downloading… {progress} · {networkSpeed} · {timeRemaining} left',
  ),
  complete: finishAlerts
      ? const bg.TaskNotification('{filename}', 'Download complete')
      : null,
  error: finishAlerts
      ? const bg.TaskNotification('{filename}', 'Download failed')
      : null,
  paused: finishAlerts
      ? const bg.TaskNotification('{filename}', 'Paused')
      : null,
  progressBar: true,
  tapOpensFile: false,
);

/// The default (alerts on) config.
final dhruvaDownloadNotificationConfig = downloadNotificationConfig();
