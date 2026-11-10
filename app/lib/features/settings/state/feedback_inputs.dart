/// Platform-facing inputs for the feedback form: the media picker and the
/// opt-in device info. Both are providers so widget tests swap them for fakes.
/// Thin glue (platform channels, no logic), like `SystemImageAttacher`.
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/di/providers.dart';
import '../../../core/feedback/feedback_report.dart';
import '../app_info.dart';

/// Phone model + OS string. Never an identifier (no Android ID / IDFV).
typedef PhoneIdentity = ({String model, String os});

final phoneIdentityProvider = FutureProvider<PhoneIdentity>((ref) async {
  final plugin = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final i = await plugin.androidInfo;
    return (
      model: '${i.manufacturer} ${i.model}',
      os: 'Android ${i.version.release} (SDK ${i.version.sdkInt})',
    );
  }
  final i = await plugin.iosInfo;
  return (model: i.utsname.machine, os: 'iOS ${i.systemVersion}');
});

/// Everything the "Include device info" box shares. Each read is best-effort:
/// a failure leaves that line "unknown" rather than blocking the report.
final feedbackDeviceInfoProvider = FutureProvider<FeedbackDeviceInfo>((
  ref,
) async {
  Future<T?> tryGet<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on Object {
      return null;
    }
  }

  final identity = await tryGet(() => ref.read(phoneIdentityProvider.future));
  final mem = await tryGet(
    () => ref.read(deviceInfoServiceProvider).getMemoryInfo(),
  );
  final disk = await tryGet(
    () => ref.read(deviceInfoServiceProvider).getStorageInfo(),
  );
  final installed =
      await tryGet(
        () => ref.read(storageManagerProvider).listInstalledModels(),
      ) ??
      const [];
  return FeedbackDeviceInfo(
    phoneModel: identity?.model ?? 'unknown',
    os: identity?.os ?? 'unknown',
    appVersion: appVersion,
    appBuild: appBuildNumber,
    // File name and size only: never the on-disk path.
    models: [for (final m in installed) FeedbackModel(m.fileName, m.sizeBytes)],
    freeRamBytes: mem?.availableBytes,
    totalRamBytes: mem?.totalBytes,
    freeStorageBytes: disk?.freeBytes,
    totalStorageBytes: disk?.totalBytes,
  );
});

/// Thrown when the OS denies photo / video access.
final class FeedbackMediaDenied implements Exception {
  const FeedbackMediaDenied();
}

abstract interface class FeedbackMediaPicker {
  /// Up to [limit] images or videos. Empty when the user cancels.
  Future<List<FeedbackAttachment>> pick(int limit);
}

final class SystemFeedbackMediaPicker implements FeedbackMediaPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<List<FeedbackAttachment>> pick(int limit) async {
    try {
      // pickMultipleMedia requires limit >= 2.
      final files = limit < 2
          ? [?await _picker.pickMedia()]
          : await _picker.pickMultipleMedia(limit: limit);
      return [
        for (final f in files)
          FeedbackAttachment(
            path: f.path,
            name: f.name,
            bytes: await f.length(),
          ),
      ];
    } on PlatformException catch (e) {
      if (e.code.contains('access_denied') || e.code == 'permission_denied') {
        throw const FeedbackMediaDenied();
      }
      rethrow;
    }
  }
}

final feedbackMediaPickerProvider = Provider<FeedbackMediaPicker>(
  (ref) => SystemFeedbackMediaPicker(),
);
