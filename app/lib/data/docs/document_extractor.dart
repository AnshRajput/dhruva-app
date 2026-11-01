/// Reads a user-picked PDF/TXT/MD file into page-tagged chunks, entirely
/// on-device and entirely off the root isolate (`Isolate.run`): reading,
/// PDF parsing and chunking of a 20 MB file never touch the UI thread.
///
/// PDF text comes from `pdf_graphics` (pure Dart, no native code, same on
/// Android and iOS). Image-only (scanned) PDFs have no text layer; they are
/// detected and reported rather than OCR'd.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'doc_chunker.dart';

/// Hard file-size limit.
const maxDocumentBytes = 20 * 1024 * 1024;

/// Hard extracted-text limit (about 100k tokens, far past any phone context
/// but the retrieval index stays small enough to hold in memory).
const maxDocumentChars = 400000;

/// A PDF with fewer characters than this has no usable text layer.
const _minUsableChars = 50;

enum DocumentKind { pdf, text, markdown }

enum DocumentFailureKind {
  tooLarge,
  tooLong,
  unsupported,
  empty,
  noText,
  unreadable,
}

/// A user-facing extraction failure. [message] is plain language, ready to
/// show as is.
final class DocumentException implements Exception {
  final DocumentFailureKind kind;
  final String message;
  const DocumentException(this.kind, this.message);

  @override
  String toString() => 'DocumentException(${kind.name}): $message';
}

/// The result of reading a document: metadata plus its chunks.
final class ExtractedDocument {
  final String name;
  final String mime;

  /// Real page count for a PDF; 0 for page-less TXT/MD.
  final int pageCount;
  final int charCount;
  final List<DocChunk> chunks;

  const ExtractedDocument({
    required this.name,
    required this.mime,
    required this.pageCount,
    required this.charCount,
    required this.chunks,
  });

  bool get paged => pageCount > 0;
}

/// Seam for the extraction step; widget tests override it with a fake that
/// skips the isolate.
typedef DocumentExtractor =
    Future<ExtractedDocument> Function(String path, String name);

/// Production extractor: validates size, then reads + parses + chunks in a
/// background isolate. Throws [DocumentException].
Future<ExtractedDocument> extractDocumentFile(String path, String name) async {
  final size = await File(path).length();
  if (size > maxDocumentBytes) {
    throw const DocumentException(
      DocumentFailureKind.tooLarge,
      'That file is over 20 MB. Choose a smaller document.',
    );
  }
  final result = await Isolate.run(() => _extractInIsolate(path, name));
  final doc = result.doc;
  if (doc == null) throw result.failure!;
  return doc;
}

/// Same as [extractDocumentFile] but on bytes already in memory and on the
/// calling isolate. Exposed for tests and for callers already off the root
/// isolate.
ExtractedDocument extractDocumentBytes(Uint8List bytes, String name) {
  if (bytes.length > maxDocumentBytes) {
    throw const DocumentException(
      DocumentFailureKind.tooLarge,
      'That file is over 20 MB. Choose a smaller document.',
    );
  }
  final kind = detectKind(name, bytes);
  if (kind == null) {
    throw const DocumentException(
      DocumentFailureKind.unsupported,
      'Dhruva can read PDF, TXT and MD files.',
    );
  }
  return switch (kind) {
    DocumentKind.pdf => _extractPdf(bytes, name),
    DocumentKind.text ||
    DocumentKind.markdown => _extractText(bytes, name, kind),
  };
}

/// Decides the document type from the file extension, falling back to the
/// `%PDF-` magic bytes. Null means unsupported.
DocumentKind? detectKind(String name, Uint8List bytes) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return DocumentKind.pdf;
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return DocumentKind.markdown;
  }
  if (lower.endsWith('.txt')) return DocumentKind.text;
  if (bytes.length > 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return DocumentKind.pdf;
  }
  return null;
}

typedef _Result = ({ExtractedDocument? doc, DocumentException? failure});

_Result _extractInIsolate(String path, String name) {
  try {
    final bytes = File(path).readAsBytesSync();
    return (doc: extractDocumentBytes(bytes, name), failure: null);
  } on DocumentException catch (e) {
    return (doc: null, failure: e);
  } on Object {
    return (
      doc: null,
      failure: const DocumentException(
        DocumentFailureKind.unreadable,
        "Couldn't read that file.",
      ),
    );
  }
}

ExtractedDocument _extractText(
  Uint8List bytes,
  String name,
  DocumentKind kind,
) {
  // Lenient: bad bytes become U+FFFD instead of failing the whole file.
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final sections = splitIntoSections(text);
  if (sections.isEmpty) {
    throw const DocumentException(
      DocumentFailureKind.empty,
      'That file is empty.',
    );
  }
  final chars = sections.fold<int>(0, (n, s) => n + s.text.length);
  _checkLength(chars);
  return ExtractedDocument(
    name: name,
    mime: kind == DocumentKind.markdown ? 'text/markdown' : 'text/plain',
    pageCount: 0,
    charCount: chars,
    chunks: chunkPages(sections),
  );
}

ExtractedDocument _extractPdf(Uint8List bytes, String name) {
  final PdfDocument doc;
  try {
    doc = PdfDocument.open(bytes);
  } on Object {
    throw const DocumentException(
      DocumentFailureKind.unreadable,
      "Couldn't open that PDF. It may be password-protected or damaged.",
    );
  }
  final pageCount = doc.pageCount;
  final pages = <PageText>[];
  var chars = 0;
  for (var i = 0; i < pageCount; i++) {
    String text;
    try {
      text = normalizeWhitespace(PdfTextExtractor.extract(doc, i).text);
    } on Object {
      continue; // one bad page must not lose the rest of the document.
    }
    if (text.isEmpty) continue;
    chars += text.length;
    _checkLength(chars);
    pages.add(PageText(i + 1, text));
  }
  if (chars < _minUsableChars) {
    throw const DocumentException(
      DocumentFailureKind.noText,
      'This PDF has no selectable text. It looks like a scan or photo of '
      'pages, which Dhruva cannot read. Try a PDF exported from a document.',
    );
  }
  return ExtractedDocument(
    name: name,
    mime: 'application/pdf',
    pageCount: pageCount,
    charCount: chars,
    chunks: chunkPages(pages),
  );
}

void _checkLength(int chars) {
  if (chars > maxDocumentChars) {
    throw const DocumentException(
      DocumentFailureKind.tooLong,
      'That document is too long (over 400,000 characters). '
      'Split it into smaller parts.',
    );
  }
}
