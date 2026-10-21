import 'package:drift/drift.dart';

import '../db/database.dart';

/// Why the user reported a reply. Stored by [name]; [label] is the UI text.
enum ReportReason {
  harmful('Harmful or dangerous'),
  sexual('Sexual content'),
  hate('Hate or harassment'),
  childSafety('Child safety'),
  misleading('False or misleading'),
  other('Other');

  final String label;
  const ReportReason(this.label);

  static ReportReason fromName(String name) => values.firstWhere(
    (r) => r.name == name,
    orElse: () => ReportReason.other,
  );
}

/// One saved report, without the drift row type (ADR-002).
final class ContentReportInfo {
  final int id;
  final DateTime createdAt;
  final int conversationId;
  final int messageId;
  final String? modelName;
  final ReportReason reason;
  final String? note;
  final String excerpt;

  const ContentReportInfo({
    required this.id,
    required this.createdAt,
    required this.conversationId,
    required this.messageId,
    this.modelName,
    required this.reason,
    this.note,
    required this.excerpt,
  });
}

/// Local-only store for user reports of assistant replies. Nothing here
/// touches the network; emailing a report is a separate, user-initiated
/// `mailto:` handoff.
final class ReportRepository {
  static const maxExcerptLength = 2000;

  final AppDatabase _db;
  const ReportRepository({required AppDatabase db}) : _db = db;

  /// Saves a report and marks the message `reported` in one transaction.
  Future<int> submit({
    required int conversationId,
    required int messageId,
    required ReportReason reason,
    required String content,
    String? modelName,
    String? note,
  }) {
    final trimmedNote = note?.trim();
    final excerpt = content.length > maxExcerptLength
        ? content.substring(0, maxExcerptLength)
        : content;
    return _db.transaction(() async {
      final id = await _db
          .into(_db.contentReports)
          .insert(
            ContentReportsCompanion.insert(
              createdAt: DateTime.now(),
              conversationId: conversationId,
              messageId: messageId,
              modelName: Value(modelName),
              reason: reason.name,
              note: Value(
                trimmedNote == null || trimmedNote.isEmpty ? null : trimmedNote,
              ),
              excerpt: excerpt,
            ),
          );
      await (_db.update(_db.messages)..where((t) => t.id.equals(messageId)))
          .write(const MessagesCompanion(reported: Value(true)));
      return id;
    });
  }

  /// Newest first.
  Stream<List<ContentReportInfo>> watchAll() {
    final q = _db.select(_db.contentReports)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return q.watch().map((rows) => [for (final r in rows) _toInfo(r)]);
  }

  Future<List<ContentReportInfo>> getAll() async {
    final q = _db.select(_db.contentReports)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return [for (final r in await q.get()) _toInfo(r)];
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.contentReports)..where((t) => t.id.equals(id))).go();
  }

  ContentReportInfo _toInfo(ContentReport r) => ContentReportInfo(
    id: r.id,
    createdAt: r.createdAt,
    conversationId: r.conversationId,
    messageId: r.messageId,
    modelName: r.modelName,
    reason: ReportReason.fromName(r.reason),
    note: r.note,
    excerpt: r.excerpt,
  );
}
