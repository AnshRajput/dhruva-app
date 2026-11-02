import 'package:dhruva/features/workflows/data/workflow_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog ids are unique and every template has an input slot', () {
    final ids = workflowCatalog.map((w) => w.id).toSet();
    expect(ids.length, workflowCatalog.length);
    expect(workflowCatalog.length, greaterThanOrEqualTo(12));
    for (final w in workflowCatalog) {
      expect('{input}'.allMatches(w.template).length, 1, reason: w.id);
      expect(w.template.contains('{option}'), w.option != null, reason: w.id);
    }
  });

  Workflow byId(String id) => workflowCatalog.firstWhere((w) => w.id == id);

  test('renders input and chosen option', () {
    final out = renderWorkflowPrompt(
      byId('translate'),
      '  namaste  ',
      'French',
    );
    expect(out, contains('into French.'));
    expect(out, endsWith('Text:\nnamaste'));
    expect(out, isNot(contains('{')));
  });

  test('option defaults to the first choice', () {
    expect(renderWorkflowPrompt(byId('rewrite'), 'hi'), contains('Formal'));
  });

  test('caps input at the limit', () {
    final out = renderWorkflowPrompt(
      byId('summarize'),
      'Z' * (workflowInputLimit + 500),
    );
    expect('Z'.allMatches(out).length, workflowInputLimit);
  });

  test('user text containing placeholders is left alone', () {
    final out = renderWorkflowPrompt(
      byId('translate'),
      'say {option}',
      'Hindi',
    );
    expect(out, endsWith('say {option}'));
  });

  test('the instruction is the template without the user text', () {
    for (final w in workflowCatalog) {
      final i = workflowInstruction(w);
      expect(i, isNot(contains('{')), reason: w.id);
      expect(i, isNot(contains('Text:')), reason: w.id);
      if (w.id != 'draft_reply') {
        expect(i, contains("user's next message"), reason: w.id);
      }
    }
    expect(
      workflowInstruction(byId('translate'), 'French'),
      contains('Translate the text into French.'),
    );
    expect(
      workflowInstruction(byId('draft_reply'), 'Short'),
      contains('Write a Short reply to the message the user sends'),
    );
  });

  test('short input is flagged only for verbs that need more text', () {
    expect(tooShortFor(byId('quiz'), 'Move standup to 10?'), isNotNull);
    expect(tooShortFor(byId('quiz'), ''), isNull);
    expect(tooShortFor(byId('quiz'), 'word ' * 12), isNull);
    expect(tooShortFor(byId('translate'), 'hi'), isNull);
  });
}
