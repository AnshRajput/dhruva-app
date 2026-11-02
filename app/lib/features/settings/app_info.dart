/// Static app-identity strings shared by the Settings screen and the About
/// page — one place so the version doesn't drift between the two surfaces.
///
/// `appVersion`/`appBuildNumber` are READ from `pubspec.yaml`'s `version:`
/// line, which is bundled as an asset (`loadAppVersion`, called once in
/// `main`), so the About line can never drift from the release version (it
/// still said 0.6.1 on a 0.7 build when the strings were typed by hand). No
/// plugin or platform channel: the pubspec is already in the app bundle, the
/// same way `shorebird.yaml` is.
library;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// `version: 0.7.0+106` split into name and build number.
final class AppVersion {
  const AppVersion(this.name, this.build);

  final String name;
  final String build;

  /// Shown only if the bundled pubspec cannot be read (never in a real build).
  static const unknown = AppVersion('0.0.0', '0');

  static AppVersion current = unknown;

  /// Reads the `version:` line of a pubspec; [unknown] when there is none.
  static AppVersion parse(String pubspec) {
    final m = RegExp(
      r'^version:\s*([0-9][^\s+#]*)(?:\+([^\s#]+))?',
      multiLine: true,
    ).firstMatch(pubspec);
    return m == null ? unknown : AppVersion(m.group(1)!, m.group(2) ?? '0');
  }
}

/// Loads [AppVersion.current] from the bundled pubspec. Never throws.
Future<void> loadAppVersion([AssetBundle? bundle]) async {
  try {
    AppVersion.current = AppVersion.parse(
      await (bundle ?? rootBundle).loadString('pubspec.yaml'),
    );
  } on Object {
    AppVersion.current = AppVersion.unknown;
  }
}

String get appVersion => AppVersion.current.name;
String get appBuildNumber => AppVersion.current.build;

const githubUrl = 'https://github.com/AnshRajput/dhruva-app';
const websiteUrl = 'https://dhruvaai.vercel.app';
const licenseUrl = 'https://github.com/AnshRajput/dhruva-app/blob/main/LICENSE';
const privacyPolicyUrl =
    'https://github.com/AnshRajput/dhruva-app/blob/main/docs/privacy.md';
const creatorUrl = 'https://anshgandharva.in';

/// "Version 0.6.0 (build 100) \u00b7 patch 2" - patch 0 is the bare release.
String versionLine(int patch) =>
    'Version $appVersion (build $appBuildNumber) \u00b7 patch $patch';

/// What long-press copies for support: "0.6.0+100 \u00b7 patch 2".
String versionCopyText(int patch) =>
    '$appVersion+$appBuildNumber \u00b7 patch $patch';
