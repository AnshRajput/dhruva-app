/// The image-capture surface the chat composer depends on (Loop 7) — same
/// discipline as `voice/mic_audio_source.dart`'s `MicSource`: `features/chat`
/// never imports `image_picker` directly, and widget tests override
/// `imageAttacherProvider` with `FakeImageAttacher` (`fake_image_attacher.
/// dart`) to drive attach/permission flows without a real OS picker.
///
/// `SystemImageAttacher` is platform glue only — it holds no logic worth
/// unit-testing and can't run under `flutter test` (needs a real photo
/// library/camera + platform channels), so it's excluded from the coverage
/// floor (same precedent as `llama_engine_service.dart`/`mic_audio_source.
/// dart`).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// Where the composer's attach sheet asked the picker to pull an image from.
enum ImageAttachSource { gallery, camera }

/// Thrown when the OS denies photo-library/camera access. A typed failure,
/// not a raw `PlatformException` — mirrors `voice_service.dart`'s
/// `VoiceValidationFailure` shape (ADR-002: typed errors at the seam).
final class ImageAttachPermissionDenied implements Exception {
  final String message;
  const ImageAttachPermissionDenied(this.message);

  @override
  String toString() => 'ImageAttachPermissionDenied: $message';
}

abstract interface class ImageAttacher {
  /// Picks one image from [source]. Returns null if the user cancelled the
  /// picker without choosing anything. Throws [ImageAttachPermissionDenied]
  /// if the OS denied access.
  Future<Uint8List?> pickImage(ImageAttachSource source);
}

final class SystemImageAttacher implements ImageAttacher {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<Uint8List?> pickImage(ImageAttachSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == ImageAttachSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
      if (file == null) return null;
      return file.readAsBytes();
    } on PlatformException catch (e) {
      // image_picker's denial codes vary by platform (iOS:
      // camera_access_denied/photo_access_denied, Android:
      // permission_denied/photo_access_denied) — treat any of them as the
      // same typed failure rather than matching one exact code per platform.
      if (e.code.contains('access_denied') || e.code == 'permission_denied') {
        throw ImageAttachPermissionDenied(e.message ?? 'permission denied');
      }
      rethrow;
    }
  }
}
