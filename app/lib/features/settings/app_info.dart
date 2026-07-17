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

const appVersion = '0.2.3';
const appBuildNumber = '3';

const githubUrl = 'https://github.com/AnshRajput/dhruva-app';
const websiteUrl = 'https://dhruvaai.vercel.app';
const licenseUrl = 'https://github.com/AnshRajput/dhruva-app/blob/main/LICENSE';
const creatorUrl = 'https://anshgandharva.online';
