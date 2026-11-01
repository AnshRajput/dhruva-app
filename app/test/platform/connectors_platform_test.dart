// Security-relevant platform declarations of the connectors (Wave 2A). These
// read the manifests / Info.plist / native sources, so a later edit that widens
// access (a WRITE permission, an unguarded listener, a schema drift between the
// Kotlin writer and the Dart reader) fails here.

import 'dart:io';

import 'package:dhruva/data/connectors/notification_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  // Strip XML comments so prose mentioning a permission is not a declaration.
  final code = manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  const kotlin =
      'third_party/dhruva_connectors/android/src/main/kotlin/tech/appuinside/'
      'dhruva/connectors';

  group('Android manifest', () {
    test('reads calendar and contacts, never writes them', () {
      expect(code, contains('android.permission.READ_CALENDAR'));
      expect(code, contains('android.permission.READ_CONTACTS'));
      for (final banned in [
        'WRITE_CALENDAR',
        'WRITE_CONTACTS',
        'MANAGE_EXTERNAL_STORAGE',
        'READ_EXTERNAL_STORAGE',
        'QUERY_ALL_PACKAGES',
        'READ_PHONE_STATE',
        'READ_SMS',
      ]) {
        expect(code, isNot(contains(banned)), reason: banned);
      }
    });

    test('the notification listener is bound only by the system', () {
      final service = RegExp(
        r'<service[^>]*NotificationCaptureService[^>]*>',
        dotAll: true,
      ).firstMatch(code)!.group(0)!;
      expect(
        service,
        contains(
          'android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"',
        ),
      );
      expect(service, contains('android:exported="true"'));
    });

    test('only the known components are exported', () {
      final exported = RegExp(
        r'<(activity|activity-alias|service|receiver|provider)\b[^>]*android:exported="true"[^>]*>',
        dotAll: true,
      ).allMatches(code).map((m) => m.group(0)!).toList();
      final names = [
        for (final e in exported)
          RegExp(r'android:name="([^"]+)"').firstMatch(e)!.group(1)!,
      ];
      expect(
        names,
        unorderedEquals([
          '.MainActivity',
          '.ProcessTextActivity',
          '.DhruvaTileService',
          '.DhruvaWidgetProvider',
          'tech.appuinside.dhruva.connectors.NotificationCaptureService',
        ]),
      );
    });

    test('the plugin manifest declares nothing (no permission sneaks in)', () {
      final pm = File(
        'third_party/dhruva_connectors/android/src/main/AndroidManifest.xml',
      ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(pm, isNot(contains('uses-permission')));
      expect(pm, isNot(contains('<service')));
    });
  });

  group('iOS Info.plist', () {
    test(
      'has the calendar (iOS 17 full access + legacy) and contacts strings',
      () {
        for (final key in [
          'NSCalendarsFullAccessUsageDescription',
          'NSCalendarsUsageDescription',
          'NSContactsUsageDescription',
        ]) {
          expect(plist, contains('<key>$key</key>'), reason: key);
        }
      },
    );

    test('does not ask for write access or background modes', () {
      expect(
        plist,
        isNot(contains('NSCalendarsWriteOnlyAccessUsageDescription')),
      );
      expect(plist, isNot(contains('UIBackgroundModes')));
    });
  });

  group('Kotlin listener <-> Dart reader agreement', () {
    final service = File(
      '$kotlin/NotificationCaptureService.kt',
    ).readAsStringSync();
    final writer = File(
      '$kotlin/NotificationQueueWriter.kt',
    ).readAsStringSync();

    test('line schema: the keys and version Dart parses', () {
      for (final key in ['v', 'pkg', 'app', 'title', 'text', 't']) {
        expect(service, contains('.put("$key"'), reason: key);
      }
      expect(service, contains('.put("v", $queueLineVersion)'));
    });

    test('file names match', () {
      expect(writer, contains('"${NotificationQueue.liveName}"'));
      expect(writer, contains('"${NotificationQueue.oldName}"'));
    });

    test('capture is off by default and checked before anything is read', () {
      expect(writer, contains('getBoolean(KEY_CAPTURE, false)'));
      expect(
        service.indexOf('captureEnabled'),
        lessThan(service.indexOf('extras')),
      );
    });

    test('the listener skips this app, dialers, user exclusions and secret '
        'notifications', () {
      for (final needle in [
        'ctx.packageName',
        'DIALERS',
        'defaultDialer',
        'ConnectorPrefs.excluded',
        'VISIBILITY_SECRET',
      ]) {
        expect(service, contains(needle), reason: needle);
      }
    });

    test('native caps are not larger than what Dart accepts', () {
      final title = int.parse(
        RegExp(r'MAX_TITLE = (\d+)').firstMatch(service)!.group(1)!,
      );
      final text = int.parse(
        RegExp(r'MAX_TEXT = (\d+)').firstMatch(service)!.group(1)!,
      );
      expect(title, lessThanOrEqualTo(maxNotificationTitleChars));
      expect(text, lessThanOrEqualTo(maxNotificationTextChars));
      final maxBytes = int.parse(
        RegExp(r'MAX_BYTES = ([\d* ]+)')
            .firstMatch(writer)!
            .group(1)!
            .split('*')
            .map((s) => int.parse(s.trim()))
            .fold(1, (a, b) => a * b)
            .toString(),
      );
      expect(maxBytes, lessThanOrEqualTo(maxQueueBytesPerDrain));
    });
  });

  group('folder access native safety', () {
    final folder = File('$kotlin/FolderAccess.kt').readAsStringSync();

    test('read-only grant, tree containment and destination checks exist', () {
      expect(folder, contains('FLAG_GRANT_READ_URI_PERMISSION'));
      expect(folder, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
      expect(folder, contains('isChildDocument'));
      expect(folder, contains('".."'));
      expect(folder, contains('cacheDir'));
      expect(folder, contains('too_large'));
    });

    test('the picker asks for a tree with a read-only persistable grant', () {
      final plugin = File(
        '$kotlin/DhruvaConnectorsPlugin.kt',
      ).readAsStringSync();
      expect(plugin, contains('ACTION_OPEN_DOCUMENT_TREE'));
      expect(plugin, contains('FLAG_GRANT_PERSISTABLE_URI_PERMISSION'));
      expect(plugin, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
    });
  });
}
