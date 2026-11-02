// Backup lockdown (daily-assistant spec B1): chats and connector data must
// never reach Google/iCloud backups. These tests read the platform files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final rules = File(
    'android/app/src/main/res/xml/data_extraction_rules.xml',
  ).readAsStringSync();

  test('manifest disables backup on every Android version', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('data extraction rules exclude every domain for both sections', () {
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(rules)!.group(1)!;
      for (final domain in [
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
      ]) {
        expect(
          body,
          contains('<exclude domain="$domain" path="."/>'),
          reason: '$section must exclude $domain',
        );
      }
      expect(body, isNot(contains('<include')));
    }
  });

  test('iOS marks Documents and Application Support excluded from backup', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('isExcludedFromBackup = true'));
    expect(swift, contains('.documentDirectory'));
    expect(swift, contains('.applicationSupportDirectory'));
    expect(swift, contains('BackupExclusion.apply()'));
  });
}
