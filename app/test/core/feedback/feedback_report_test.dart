// FeedbackReport: the pure builder that decides exactly what the email draft
// contains. One test per behaviour.

import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/feedback/feedback_report.dart';
import 'package:flutter_test/flutter_test.dart';

const _info = FeedbackDeviceInfo(
  phoneModel: 'Google Pixel 8',
  os: 'Android 14 (SDK 34)',
  appVersion: '0.7.0',
  appBuild: '106',
  models: [FeedbackModel('gemma-3-1b-it-Q4_K_M.gguf', 800 * 1024 * 1024)],
  freeRamBytes: 3 * 1024 * 1024 * 1024,
  totalRamBytes: 8 * 1024 * 1024 * 1024,
  freeStorageBytes: 20 * 1024 * 1024 * 1024,
  totalStorageBytes: 128 * 1024 * 1024 * 1024,
);

final _crash = CrashRecord(
  timestamp: DateTime.utc(2026, 5, 1),
  appVersion: '0.7.0',
  appBuild: '106',
  platform: 'android',
  osVersion: '14',
  errorType: 'StateError',
  message: 'boom',
  stack: 'stack here',
);

FeedbackAttachment _file(int bytes, [String name = 'a.png']) =>
    FeedbackAttachment(path: '/cache/$name', name: name, bytes: bytes);

void main() {
  test('bug: subject tag and plain-text body with steps', () {
    final r = buildFeedbackReport(
      const FeedbackDraft(
        type: FeedbackType.bug,
        title: '  Chat\nfreezes  ',
        description: 'It froze.\nI expected a reply.',
        steps: '1. Open chat\n2. Send',
      ),
      version: '0.7.0',
    );
    expect(r.subject, '[Dhruva 0.7.0][Bug] Chat freezes');
    expect(
      r.body,
      'Type: Bug\n'
      'Title: Chat freezes\n'
      '\n'
      'Description:\n'
      'It froze.\nI expected a reply.\n'
      '\n'
      'Steps to reproduce:\n'
      '1. Open chat\n2. Send',
    );
  });

  test('feature: subject tag, and steps are never included', () {
    final r = buildFeedbackReport(
      const FeedbackDraft(
        type: FeedbackType.feature,
        title: 'Dark widget',
        description: 'A dark home widget.',
        steps: 'leftover from the bug tab',
      ),
      version: '0.7.0',
    );
    expect(r.subject, '[Dhruva 0.7.0][Feature] Dark widget');
    expect(r.body, startsWith('Type: Feature\nTitle: Dark widget'));
    expect(r.body, isNot(contains('Steps to reproduce')));
    expect(r.body, isNot(contains('leftover')));
  });

  test('device info block is in the body only when ticked', () {
    const base = FeedbackDraft(
      type: FeedbackType.bug,
      title: 't',
      description: 'd',
    );
    final off = buildFeedbackReport(base, version: '0.7.0');
    expect(off.body, isNot(contains('Device info')));
    expect(off.body, isNot(contains('Pixel')));

    final on = buildFeedbackReport(
      FeedbackDraft(
        type: base.type,
        title: 't',
        description: 'd',
        deviceInfo: _info,
      ),
      version: '0.7.0',
    );
    expect(on.body, contains('Phone: Google Pixel 8'));
    expect(on.body, contains('OS: Android 14 (SDK 34)'));
    expect(on.body, contains('App: Dhruva 0.7.0 (build 106)'));
    expect(
      on.body,
      contains('Installed models: gemma-3-1b-it-Q4_K_M.gguf (800 MB)'),
    );
    expect(on.body, contains('Free RAM: 3.0 GB of 8.0 GB'));
    expect(on.body, contains('Free storage: 20.0 GB of 128.0 GB'));
    // No file-system paths or identifiers anywhere.
    expect(on.body, isNot(contains('/data/')));
  });

  test('crash log text exists only when ticked and a crash exists', () {
    FeedbackDraft draft(List<CrashRecord>? c) => FeedbackDraft(
      type: FeedbackType.bug,
      title: 't',
      description: 'd',
      crashRecords: c,
    );
    expect(
      buildFeedbackReport(draft(null), version: '0.7.0').crashLogText,
      isNull,
    );
    expect(
      buildFeedbackReport(draft([]), version: '0.7.0').crashLogText,
      isNull,
    );
    final on = buildFeedbackReport(draft([_crash]), version: '0.7.0');
    expect(on.crashLogText, contains('StateError: boom'));
    // The body itself never carries the log.
    expect(on.body, isNot(contains('StateError')));
  });

  test('media paths are attachments; the body only counts them', () {
    final r = buildFeedbackReport(
      FeedbackDraft(
        type: FeedbackType.bug,
        title: 't',
        description: 'd',
        attachments: [_file(10), _file(20, 'b.mp4')],
      ),
      version: '0.7.0',
    );
    expect(r.mediaPaths, ['/cache/a.png', '/cache/b.mp4']);
    expect(r.body, isNot(contains('/cache')));
  });

  test('attachment limits: at most 5 files', () {
    final five = [for (var i = 0; i < 5; i++) _file(1, '$i.png')];
    expect(checkAttachmentLimits(five.sublist(0, 4), [five.last]), isNull);
    expect(
      checkAttachmentLimits(five, [_file(1, 'x.png')]),
      'You can add up to 5 files. Remove one to add another.',
    );
  });

  test('attachment limits: total under 20 MB', () {
    const mb = 1024 * 1024;
    expect(checkAttachmentLimits([_file(10 * mb)], [_file(10 * mb)]), isNull);
    expect(
      checkAttachmentLimits([_file(10 * mb)], [_file(10 * mb + 1)]),
      'Files together must be under 20 MB. '
      'Remove one or pick a smaller one.',
    );
  });

  test('title and description are required; title under 120', () {
    expect(validateFeedbackTitle('  '), 'Add a short title.');
    expect(validateFeedbackTitle('a' * 120), isNull);
    expect(
      validateFeedbackTitle('a' * 121),
      'Keep the title under 120 characters.',
    );
    expect(validateFeedbackDescription(' \n'), 'Tell us a little more.');
    expect(validateFeedbackDescription('x'), isNull);
  });

  test('preview names exactly what is shared', () {
    expect(
      feedbackPreview(const FeedbackDraft(type: FeedbackType.bug, title: 't')),
      'This will share: your title and description.',
    );
    final all = feedbackPreview(
      FeedbackDraft(
        type: FeedbackType.bug,
        steps: 's',
        attachments: [_file(1)],
        deviceInfo: _info,
        crashRecords: [_crash],
      ),
    );
    expect(all, contains('your steps'));
    expect(all, contains('1 file'));
    expect(all, contains('phone model, OS, app version'));
    expect(all, contains('the recent crash log'));
  });

  test('description prompt differs per type', () {
    expect(
      FeedbackType.bug.descriptionPrompt,
      'What happened? What did you expect?',
    );
    expect(
      FeedbackType.feature.descriptionPrompt,
      'What would you like Dhruva to do?',
    );
  });
}
