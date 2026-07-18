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

/// The one, global download-notification config. Progress bar on (Android);
/// `tapOpensFile` off — GGUF/voice bundles aren't user-openable files.
final dhruvaDownloadNotificationConfig = bg.TaskNotificationConfig(
  running: const bg.TaskNotification(
    '{filename}',
    'Downloading… {progress} · {networkSpeed} · {timeRemaining} left',
  ),
  complete: const bg.TaskNotification('{filename}', 'Download complete'),
  error: const bg.TaskNotification('{filename}', 'Download failed'),
  paused: const bg.TaskNotification('{filename}', 'Paused'),
  progressBar: true,
  tapOpensFile: false,
);
