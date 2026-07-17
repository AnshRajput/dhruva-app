/// In-memory [ImageAttacher] for widget tests (same seam as
/// `voice/fake_mic_source.dart`'s `FakeMicSource`) — drives the composer's
/// attach flow without a real photo library/camera.
library;

import 'dart:typed_data';

import 'image_attach_source.dart';

final class FakeImageAttacher implements ImageAttacher {
  /// Bytes returned by the next [pickImage] call, or null to simulate the
  /// user cancelling the picker.
  Uint8List? nextImage;

  /// When true, [pickImage] throws [ImageAttachPermissionDenied] instead of
  /// returning [nextImage].
  bool permissionDenied = false;

  /// Test hook: which source the composer most recently asked for.
  ImageAttachSource? lastSource;

  /// Test hook: number of [pickImage] calls.
  int pickCount = 0;

  @override
  Future<Uint8List?> pickImage(ImageAttachSource source) async {
    lastSource = source;
    pickCount++;
    if (permissionDenied) {
      throw const ImageAttachPermissionDenied('access denied');
    }
    return nextImage;
  }
}
