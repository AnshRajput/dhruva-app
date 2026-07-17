import 'dart:async';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/data/hf_api/models/hf_search_result.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'hung request surfaces NetworkOfflineFailure after the timeout '
    'instead of spinning forever',
    () {
      fakeAsync((async) {
        final client = HfApiClient(
          client: MockClient((request) {
            return Completer<http.Response>().future; // hangs forever
          }),
        );
        AppFailure? failure;
        unawaited(
          client
              .searchGgufModels(query: 'llama')
              .then<void>((_) {})
              .catchError((Object e) {
                failure = e as AppFailure;
              }),
        );
        async.elapse(HfApiClient.requestTimeout + const Duration(seconds: 1));
        expect(failure, isA<NetworkOfflineFailure>());
        expect('${failure!.message}', contains('timed out'));
      });
    },
  );
}
