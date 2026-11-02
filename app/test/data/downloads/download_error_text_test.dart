// A failed download used to show the OS text verbatim: "unknown error" on
// iOS when nsurlsessiond was unreachable. Users need plain words + a next step.
import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:dhruva/data/downloads/background_downloader_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the iOS "unknown error" becomes a retry hint, never OS text', () {
    final text = downloadErrorText(bg.TaskException('unknown error'));
    expect(text, "The download couldn't start. Tap retry.");
  });

  test('HTTP and connection failures get specific words', () {
    expect(
      downloadErrorText(bg.TaskHttpException('nf', 404)),
      contains('no longer on Hugging Face'),
    );
    expect(
      downloadErrorText(bg.TaskHttpException('x', 403)),
      contains('refused'),
    );
    expect(
      downloadErrorText(bg.TaskHttpException('x', 503)),
      contains('error 503'),
    );
    expect(
      downloadErrorText(bg.TaskConnectionException('offline')),
      contains('No connection'),
    );
    expect(
      downloadErrorText(bg.TaskFileSystemException('ENOSPC')),
      contains('Free up some space'),
    );
  });
}
