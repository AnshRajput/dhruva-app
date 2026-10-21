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
}
