/// In-memory [DocumentPicker] for widget tests (same seam as
/// `vision/fake_image_attacher.dart`).
library;

import 'document_picker.dart';

final class FakeDocumentPicker implements DocumentPicker {
  /// Returned by the next [pickDocument], or null to simulate cancelling.
  PickedDocument? next;

  /// Number of [pickDocument] calls.
  int pickCount = 0;

  @override
  Future<PickedDocument?> pickDocument() async {
    pickCount++;
    return next;
  }
}
