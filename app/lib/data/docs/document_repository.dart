import 'package:drift/drift.dart';

import '../db/database.dart';
import 'document_extractor.dart';
import 'grounding.dart';

/// One `AttachedDocuments` row, surfaced without the drift-generated type
/// (ADR-002: `features/` never imports drift directly).
final class DocumentInfo {
  /// Positive for a stored document; negative for one that is extracted but
  /// waiting for its conversation to exist (a brand-new draft chat).
  final int id;
  final int conversationId;
  final String name;
  final String mime;
  final int pageCount;
  final int charCount;
  final DateTime createdAt;

  const DocumentInfo({
    required this.id,
    required this.conversationId,
    required this.name,
    required this.mime,
    required this.pageCount,
    required this.charCount,
    required this.createdAt,
  });

  bool get paged => pageCount > 0;

  /// "12 pages · 14,498 characters" (PDF) or "3,200 characters" (TXT/MD).
  String get sizeLabel {
    final chars = '${_grouped(charCount)} characters';
    if (!paged) return chars;
    return '$pageCount ${pageCount == 1 ? 'page' : 'pages'} · $chars';
  }
}

String _grouped(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// Documents attached to conversations and their retrievable chunks.
final class DocumentRepository {
  final AppDatabase _db;
  const DocumentRepository({required AppDatabase db}) : _db = db;

  /// Stores [doc] and all its chunks for [conversationId] in one
  /// transaction.
  Future<DocumentInfo> addDocument(int conversationId, ExtractedDocument doc) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final id = await _db
          .into(_db.attachedDocuments)
          .insert(
            AttachedDocumentsCompanion.insert(
              conversationId: conversationId,
              name: doc.name,
              mime: doc.mime,
              pageCount: Value(doc.pageCount),
              charCount: Value(doc.charCount),
              createdAt: now,
            ),
          );
      await _db.batch((b) {
        b.insertAll(_db.documentChunks, [
          for (final c in doc.chunks)
            DocumentChunksCompanion.insert(
              documentId: id,
              chunkIndex: c.index,
              page: c.page,
              body: c.text,
            ),
        ]);
      });
      return DocumentInfo(
        id: id,
        conversationId: conversationId,
        name: doc.name,
        mime: doc.mime,
        pageCount: doc.pageCount,
        charCount: doc.charCount,
        createdAt: now,
      );
    });
  }

  /// Oldest first.
  Future<List<DocumentInfo>> listDocuments(int conversationId) async {
    final rows =
        await (_db.select(_db.attachedDocuments)
              ..where((t) => t.conversationId.equals(conversationId))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    return [
      for (final r in rows)
        DocumentInfo(
          id: r.id,
          conversationId: r.conversationId,
          name: r.name,
          mime: r.mime,
          pageCount: r.pageCount,
          charCount: r.charCount,
          createdAt: r.createdAt,
        ),
    ];
  }

  /// Removes the document and (FK cascade) its chunks.
  Future<void> removeDocument(int id) async {
    await (_db.delete(
      _db.attachedDocuments,
    )..where((t) => t.id.equals(id))).go();
  }

  /// Every chunk of every document attached to [conversationId], in
  /// (document, chunk) order — the corpus one question is searched over.
  Future<List<StoredChunk>> chunksFor(int conversationId) async {
    final query =
        _db.select(_db.documentChunks).join([
            innerJoin(
              _db.attachedDocuments,
              _db.attachedDocuments.id.equalsExp(_db.documentChunks.documentId),
            ),
          ])
          ..where(_db.attachedDocuments.conversationId.equals(conversationId))
          ..orderBy([
            OrderingTerm.asc(_db.attachedDocuments.id),
            OrderingTerm.asc(_db.documentChunks.chunkIndex),
          ]);
    final rows = await query.get();
    return [
      for (final row in rows)
        StoredChunk(
          docId: row.readTable(_db.attachedDocuments).id,
          docName: row.readTable(_db.attachedDocuments).name,
          paged: row.readTable(_db.attachedDocuments).pageCount > 0,
          index: row.readTable(_db.documentChunks).chunkIndex,
          page: row.readTable(_db.documentChunks).page,
          text: row.readTable(_db.documentChunks).body,
        ),
    ];
  }
}
