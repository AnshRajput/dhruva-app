// The privacy facts list is the user-visible contract: pin it, so adding a
// network call without updating the screen (or vice versa) fails a test.

import 'package:dhruva/features/settings/privacy_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exactly the four stated network calls, in order', () {
    expect(networkFacts.map((f) => f.title), [
      'Model downloads',
      'AI news',
      'Update checks',
      'Your own accounts',
    ]);
  });

  test('reports are drafts in the email app, not a network call', () {
    expect(
      reportsFact,
      'Reports you write open in your email app; nothing is sent until you '
      'send it there.',
    );
  });

  test('the facts name the real parties and promise nothing false', () {
    final all = networkFacts.map((f) => '${f.title} ${f.body}').join(' ');
    expect(all, contains('Hugging Face'));
    expect(all, contains('patch number'));
    expect(all, contains('Shorebird'));
    expect(all, contains('IP address'));
    expect(all, contains('Automatic when you open the app'));
    expect(all, isNot(contains('Gmail')));
    expect(all.toLowerCase(), isNot(contains('analytics')));
    expect(noServerFact, 'There is no Dhruva server.');
    expect(backupsOffFact, contains('Backups are off'));
    expect(backupsOffFact, contains('new phone'));
  });
}
