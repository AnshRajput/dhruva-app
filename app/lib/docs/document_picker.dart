/// The file-picking surface the chat composer depends on for "chat with a
/// document" — same discipline as `vision/image_attach_source.dart`:
/// `features/chat` never imports `file_selector` directly, and widget tests
/// override `documentPickerProvider` with `FakeDocumentPicker`.
///
/// `SystemDocumentPicker` is platform glue only (needs a real OS picker), so
/// it is excluded from the coverage floor, like the image/mic adapters.
library;

import 'package:file_selector/file_selector.dart';

/// A file the user chose. [path] is readable by this process (file_selector
/// copies Android content URIs into the app cache).
final class PickedDocument {
  final String name;
  final String path;
  const PickedDocument({required this.name, required this.path});
}

abstract interface class DocumentPicker {
  /// Opens the OS picker for PDF/TXT/MD files. Null if the user cancelled.
  Future<PickedDocument?> pickDocument();
}

final class SystemDocumentPicker implements DocumentPicker {
  const SystemDocumentPicker();

  @override
  Future<PickedDocument?> pickDocument() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documents',
          extensions: ['pdf', 'txt', 'md', 'markdown'],
          // Android filters by MIME type (markdown has no single standard
          // one); iOS filters by UTI.
          mimeTypes: [
            'application/pdf',
            'text/plain',
            'text/markdown',
            'text/x-markdown',
          ],
          uniformTypeIdentifiers: [
            'com.adobe.pdf',
            'public.plain-text',
            'net.daringfireball.markdown',
          ],
        ),
      ],
    );
    if (file == null) return null;
    return PickedDocument(name: file.name, path: file.path);
  }
}
