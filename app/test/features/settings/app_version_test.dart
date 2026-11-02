// The version shown in About comes from pubspec.yaml, never from a typed copy.

import 'dart:io';

import 'package:dhruva/features/settings/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle needs a binding
  test('parse reads name and build from the version line', () {
    final v = AppVersion.parse('name: x\nversion: 0.7.0+106\nenvironment:\n');
    expect(v.name, '0.7.0');
    expect(v.build, '106');
  });

  test('a version without a build number gets build 0', () {
    expect(AppVersion.parse('version: 1.2.3\n').build, '0');
  });

  test('no version line is "unknown", never a crash', () {
    expect(AppVersion.parse('name: x\n'), AppVersion.unknown);
  });

  test(
    'the bundled pubspec is what the app reads (matches the file)',
    () async {
      await loadAppVersion();
      final onDisk = AppVersion.parse(File('pubspec.yaml').readAsStringSync());
      expect(onDisk, isNot(AppVersion.unknown));
      expect(appVersion, onDisk.name);
      expect(appBuildNumber, onDisk.build);
      expect(
        versionLine(2),
        'Version ${onDisk.name} (build ${onDisk.build}) · patch 2',
      );
    },
  );
}
