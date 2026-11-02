import 'dart:async';
import 'dart:io' show SocketException;

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/core/failures/failure_message.dart';
import 'package:dhruva/data/downloads/background_downloader_backend.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/mock_hf_client.dart';

void main() {
  test('hung request surfaces NetworkOfflineFailure after the timeout '
      'instead of spinning forever', () {
    fakeAsync((async) {
      final client = mockHfClient(
        MockClient((request) {
          return Completer<http.Response>().future; // hangs forever
        }),
      );
      AppFailure? failure;
      unawaited(
        client.searchGgufModels(query: 'llama').then<void>((_) {}).catchError((
          Object e,
        ) {
          failure = e as AppFailure;
        }),
      );
      async.elapse(HfApiClient.requestTimeout + const Duration(seconds: 1));
      expect(failure, isA<NetworkOfflineFailure>());
      expect(failure!.message, contains('timed out'));
    });
  });

  test(
    'no connection reads in plain words, same as a failed transfer',
    () async {
      final client = mockHfClient(
        MockClient((_) async => throw const SocketException('offline')),
      );
      await expectLater(
        client.searchGgufModels(query: 'llama'),
        throwsA(
          isA<NetworkOfflineFailure>().having(
            (f) => f.message,
            'message',
            kNoConnectionMessage,
          ),
        ),
      );
      expect(
        downloadErrorText(bg.TaskConnectionException('offline')),
        kNoConnectionMessage,
      );
    },
  );
}
