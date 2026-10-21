/// Static app-identity strings shared by the Settings screen and the About
/// page — one place so the version doesn't drift between the two surfaces.
///
/// `appVersion`/`appBuildNumber` are kept in sync with `pubspec.yaml`'s
/// `version:` field by hand. `package_info_plus` would read these at
/// runtime, but for two static strings shown on two screens, a dependency
/// (plus its platform channel, plus mocking it in every test that touches
/// either screen) is heavier than the strings themselves. Bump these
/// alongside `pubspec.yaml` on release.
library;

const appVersion = '0.6.0';
const appBuildNumber = '100';

const githubUrl = 'https://github.com/AnshRajput/dhruva-app';
const websiteUrl = 'https://dhruvaai.vercel.app';
const licenseUrl = 'https://github.com/AnshRajput/dhruva-app/blob/main/LICENSE';
const creatorUrl = 'https://anshgandharva.in';

/// "Version 0.6.0 (build 100) \u00b7 patch 2" - patch 0 is the bare release.
String versionLine(int patch) =>
    'Version $appVersion (build $appBuildNumber) \u00b7 patch $patch';

/// What long-press copies for support: "0.6.0+100 \u00b7 patch 2".
String versionCopyText(int patch) =>
    '$appVersion+$appBuildNumber \u00b7 patch $patch';
