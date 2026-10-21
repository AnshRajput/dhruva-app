import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/safety/report_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ChatRepository chat;
  late ReportRepository reports;
  late int convoId;
  late int msgId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    chat = ChatRepository(db: db);
    reports = ReportRepository(db: db);
    convoId = await chat.createConversation();
    msgId = await chat.appendMessage(
      conversationId: convoId,
      role: MessageRole.assistant,
      content: 'a reply',
    );
  });

  tearDown(() => db.close());

  test('submit saves the report and marks the message reported', () async {
    await reports.submit(
      conversationId: convoId,
      messageId: msgId,
      reason: ReportReason.harmful,
      content: 'a reply',
      modelName: 'tiny.gguf',
      note: '  too dangerous ',
    );
    final all = await reports.getAll();
    expect(all, hasLength(1));
    expect(all.single.reason, ReportReason.harmful);
    expect(all.single.note, 'too dangerous');
    expect(all.single.modelName, 'tiny.gguf');
    expect(all.single.excerpt, 'a reply');
    final msgs = await chat.getMessages(convoId);
    expect(msgs.single.reported, isTrue);
  });

  test('blank note is stored as null; excerpt is capped at 2000', () async {
    await reports.submit(
      conversationId: convoId,
      messageId: msgId,
      reason: ReportReason.other,
      content: 'x' * 3000,
      note: '   ',
    );
    final r = (await reports.getAll()).single;
    expect(r.note, isNull);
    expect(r.excerpt.length, ReportRepository.maxExcerptLength);
  });

  test('newest first; delete removes only that report', () async {
    final a = await reports.submit(
      conversationId: convoId,
      messageId: msgId,
      reason: ReportReason.sexual,
      content: 'one',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = await reports.submit(
      conversationId: convoId,
      messageId: msgId,
      reason: ReportReason.hate,
      content: 'two',
    );
    expect((await reports.getAll()).map((r) => r.id), [b, a]);
    await reports.delete(b);
    expect((await reports.getAll()).map((r) => r.id), [a]);
  });

  test('reports survive deleting the conversation', () async {
    await reports.submit(
      conversationId: convoId,
      messageId: msgId,
      reason: ReportReason.childSafety,
      content: 'r',
    );
    await chat.deleteConversation(convoId);
    expect(await reports.getAll(), hasLength(1));
  });

  test('unknown stored reason falls back to other', () {
    expect(ReportReason.fromName('nope'), ReportReason.other);
  });
}
