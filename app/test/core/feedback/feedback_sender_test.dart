// sendFeedback: email draft first, share-sheet fallback when the mail app is
// unavailable. The platform sits behind FeedbackTransport, faked here.

import 'package:dhruva/core/feedback/feedback_report.dart';
import 'package:dhruva/core/feedback/feedback_sender.dart';
import 'package:dhruva/core/safety/report_mail.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements FeedbackTransport {
  _FakeTransport({this.emailAvailable = true});
  final bool emailAvailable;
  final staged = <String, String>{};
  Map<String, Object?>? email;
  Map<String, Object?>? shared;

  @override
  Future<String> stageText(String fileName, String text) async {
    staged[fileName] = text;
    return '/tmp/$fileName';
  }

  @override
  Future<void> composeEmail({
    required String to,
    required String subject,
    required String body,
    required List<String> attachmentPaths,
  }) async {
    if (!emailAvailable) throw const EmailUnavailable('not_available');
    email = {
      'to': to,
      'subject': subject,
      'body': body,
      'files': attachmentPaths,
    };
  }

  @override
  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  }) async {
    shared = {'text': text, 'subject': subject, 'files': filePaths};
  }
}

const _report = FeedbackReport(
  subject: '[Dhruva 0.7.0][Bug] t',
  body: 'Type: Bug\nTitle: t',
  mediaPaths: ['/cache/a.png'],
  crashLogText: null,
);

void main() {
  test(
    'text-only share passes no files (share_plus rejects an empty list)',
    () {
      final p = feedbackShareParams(
        text: 't',
        subject: 's',
        filePaths: const [],
      );
      expect(p.files, isNull);
      expect(p.text, 't');
    },
  );

  test('share with attachments still passes the files', () {
    final p = feedbackShareParams(
      text: 't',
      subject: 's',
      filePaths: const ['/cache/a.png', '/tmp/crash-log.txt'],
    );
    expect(p.files!.map((f) => f.path), ['/cache/a.png', '/tmp/crash-log.txt']);
  });

  test(
    'text-only email passes no attachment list; with files it passes them',
    () {
      final none = feedbackEmail(
        to: developerEmail,
        subject: 's',
        body: 'b',
        attachmentPaths: const [],
      );
      expect(none.attachmentPaths, isNull);
      expect(none.recipients, [developerEmail]);

      final some = feedbackEmail(
        to: developerEmail,
        subject: 's',
        body: 'b',
        attachmentPaths: const ['/cache/a.png'],
      );
      expect(some.attachmentPaths, ['/cache/a.png']);
    },
  );

  test(
    'share path is always available: address first, full body, files',
    () async {
      final t = _FakeTransport(); // mail app "available": share still works
      final how = await shareFeedback(
        const FeedbackReport(
          subject: '[Dhruva 0.7.0][Bug] t',
          body: 'Type: Bug\nTitle: t\n\nDescription:\nIt broke.',
          mediaPaths: ['/cache/a.png'],
          crashLogText: 'StateError: boom',
        ),
        t,
      );
      expect(how, FeedbackHandoff.shareSheet);
      expect(t.email, isNull);
      expect(
        t.shared!['text'],
        'Please send to $developerEmail\n\n'
        'Type: Bug\nTitle: t\n\nDescription:\nIt broke.',
      );
      expect(t.shared!['files'], ['/cache/a.png', '/tmp/crash-log.txt']);
    },
  );

  test(
    'mail app available: composes to the developer with attachments',
    () async {
      final t = _FakeTransport();
      final how = await sendFeedback(_report, t);
      expect(how, FeedbackHandoff.emailDraft);
      expect(t.email, {
        'to': developerEmail,
        'subject': '[Dhruva 0.7.0][Bug] t',
        'body': 'Type: Bug\nTitle: t',
        'files': ['/cache/a.png'],
      });
      expect(t.shared, isNull);
    },
  );

  test(
    'mail app unavailable: share sheet with the address first, same files',
    () async {
      final t = _FakeTransport(emailAvailable: false);
      final how = await sendFeedback(_report, t);
      expect(how, FeedbackHandoff.shareSheet);
      expect(
        t.shared!['text'],
        'Please send to $developerEmail\n\nType: Bug\nTitle: t',
      );
      expect(t.shared!['subject'], '[Dhruva 0.7.0][Bug] t');
      expect(t.shared!['files'], ['/cache/a.png']);
    },
  );

  test(
    'crash-log.txt is staged and attached only when the report has one',
    () async {
      final none = _FakeTransport();
      await sendFeedback(_report, none);
      expect(none.staged, isEmpty);

      final t = _FakeTransport();
      await sendFeedback(
        const FeedbackReport(
          subject: 's',
          body: 'b',
          mediaPaths: ['/cache/a.png'],
          crashLogText: 'StateError: boom',
        ),
        t,
      );
      expect(t.staged, {'crash-log.txt': 'StateError: boom'});
      expect(t.email!['files'], ['/cache/a.png', '/tmp/crash-log.txt']);
    },
  );
}
