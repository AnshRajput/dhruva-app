import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/docs/doc_chunker.dart';
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:dhruva/data/docs/document_repository.dart';
import 'package:dhruva/data/docs/grounding.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ExtractedDocument extracted(String name, {int pages = 2}) => ExtractedDocument(
  name: name,
  mime: pages > 0 ? 'application/pdf' : 'text/plain',
  pageCount: pages,
  charCount: 1234,
  chunks: [
    const DocChunk(index: 0, page: 1, text: 'first chunk'),
    const DocChunk(index: 1, page: 1, text: 'second chunk'),
    const DocChunk(index: 2, page: 2, text: 'third chunk'),
  ],
);

void main() {
  late AppDatabase db;
  late DocumentRepository docs;
  late ChatRepository chat;
  late int convoA;
  late int convoB;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    docs = DocumentRepository(db: db);
    chat = ChatRepository(db: db);
    convoA = await chat.createConversation();
    convoB = await chat.createConversation();
  });

  tearDown(() => db.close());

  test('stores a document with its chunks and lists it', () async {
    final info = await docs.addDocument(convoA, extracted('a.pdf'));
    expect(info.id, greaterThan(0));
    expect(info.sizeLabel, '2 pages · 1,234 characters');

    final listed = await docs.listDocuments(convoA);
    expect(listed.single.name, 'a.pdf');
    expect(listed.single.charCount, 1234);
    expect(await docs.listDocuments(convoB), isEmpty);
  });

  test('chunksFor returns only that conversation, in document order, with '
      'citation metadata', () async {
    await docs.addDocument(convoA, extracted('a.pdf'));
    await docs.addDocument(convoA, extracted('b.txt', pages: 0));
    await docs.addDocument(convoB, extracted('other.pdf'));

    final chunks = await docs.chunksFor(convoA);
    expect(chunks, hasLength(6));
    expect(chunks.map((c) => c.docName).toSet(), {'a.pdf', 'b.txt'});
    expect(chunks.take(3).map((c) => c.index), [0, 1, 2]);
    expect(chunks.first.paged, isTrue);
    expect(chunks.last.paged, isFalse);
    expect(chunks[2].page, 2);
    expect(chunks.first.text, 'first chunk');
  });

  test('removeDocument deletes its chunks and leaves siblings alone', () async {
    final a = await docs.addDocument(convoA, extracted('a.pdf'));
    await docs.addDocument(convoA, extracted('b.pdf'));
    await docs.removeDocument(a.id);
    expect((await docs.listDocuments(convoA)).single.name, 'b.pdf');
    expect(await docs.chunksFor(convoA), hasLength(3));
  });

  test('deleting a conversation cascades to documents and chunks', () async {
    await docs.addDocument(convoA, extracted('a.pdf'));
    await docs.addDocument(convoB, extracted('b.pdf'));
    await chat.deleteConversation(convoA);
    expect(await docs.listDocuments(convoA), isEmpty);
    expect(await docs.chunksFor(convoA), isEmpty);
    expect(await docs.chunksFor(convoB), hasLength(3));
    expect(await db.select(db.documentChunks).get(), hasLength(3));
  });

  test('message sources round-trip through ChatRepository', () async {
    final id = await chat.appendMessage(
      conversationId: convoA,
      role: MessageRole.assistant,
      content: 'Two years [p.2].',
    );
    await chat.setSources(id, const [
      DocSource(docName: 'a.pdf', page: 2, paged: true, snippet: 'two years'),
    ]);
    final msg = (await chat.getMessages(convoA)).single;
    expect(msg.sources.single.page, 2);
    expect(msg.sources.single.snippet, 'two years');
    await chat.setSources(id, const []);
    expect((await chat.getMessages(convoA)).single.sources, isEmpty);
  });

  test('sizeLabel for page-less and single-page documents', () {
    DocumentInfo info(int pages) => DocumentInfo(
      id: 1,
      conversationId: 1,
      name: 'x',
      mime: 'x',
      pageCount: pages,
      charCount: 5,
      createdAt: DateTime.utc(2026),
    );
    expect(info(0).sizeLabel, '5 characters');
    expect(info(1).sizeLabel, '1 page · 5 characters');
  });
}
