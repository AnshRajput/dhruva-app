import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/features/models_hub/state/model_search_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _fixture(String name) =>
    File('test/data/hf_api/fixtures/$name').readAsStringSync();

ProviderContainer _containerWith(
  http.Response Function(http.Request) responder,
) {
  final container = ProviderContainer(
    overrides: [
      hfApiClientProvider.overrideWithValue(
        HfApiClient(client: MockClient((request) async => responder(request))),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('build() runs an empty-query search on startup', () async {
    final container = _containerWith(
      (request) => http.Response(_fixture('search_gguf.json'), 200),
    );
    final state = await container.read(modelSearchControllerProvider.future);
    expect(state.query, '');
    expect(state.items, hasLength(3));
    expect(state.hasMore, isFalse);
  });

  test('search() replaces the results for a new query', () async {
    final container = _containerWith(
      (request) => http.Response(_fixture('search_gguf.json'), 200),
    );
    await container.read(modelSearchControllerProvider.future);

    await container.read(modelSearchControllerProvider.notifier).search('qwen');
    final state = container.read(modelSearchControllerProvider).value!;
    expect(state.query, 'qwen');
    expect(state.items, hasLength(3));
  });

  test('search() surfaces a typed failure via AsyncError', () async {
    final container = _containerWith(
      (request) => http.Response('server error', 500),
    );
    // Initial build() also fails against this responder — read `.notifier`
    // directly rather than `.future` so that startup failure doesn't throw
    // here; `search()`'s own error handling is what's under test.
    await container.read(modelSearchControllerProvider.notifier).search('x');
    final asyncState = container.read(modelSearchControllerProvider);
    expect(asyncState.hasError, isTrue);
    expect(asyncState.error, isA<NetworkHttpFailure>());
  });

  test('loadMore() appends the next page and advances the cursor', () async {
    var call = 0;
    final container = _containerWith((request) {
      call++;
      if (call == 1) {
        return http.Response(
          _fixture('search_gguf.json'),
          200,
          headers: {
            'link':
                '<https://huggingface.co/api/models?cursor=page2>; rel="next"',
          },
        );
      }
      return http.Response(jsonEncode([]), 200);
    });
    await container.read(modelSearchControllerProvider.future);
    expect(
      container.read(modelSearchControllerProvider).value!.hasMore,
      isTrue,
    );

    await container.read(modelSearchControllerProvider.notifier).loadMore();

    final state = container.read(modelSearchControllerProvider).value!;
    expect(state.items, hasLength(3)); // page 2 was empty
    expect(state.hasMore, isFalse);
    expect(state.loadingMore, isFalse);
  });

  test('loadMore() failure sets loadMoreError without losing page 1', () async {
    var call = 0;
    final container = _containerWith((request) {
      call++;
      if (call == 1) {
        return http.Response(
          _fixture('search_gguf.json'),
          200,
          headers: {
            'link':
                '<https://huggingface.co/api/models?cursor=page2>; rel="next"',
          },
        );
      }
      return http.Response('rate limited', 429);
    });
    await container.read(modelSearchControllerProvider.future);

    await container.read(modelSearchControllerProvider.notifier).loadMore();

    final state = container.read(modelSearchControllerProvider).value!;
    expect(state.items, hasLength(3)); // page 1 preserved
    expect(state.loadMoreError, isA<NetworkRateLimitFailure>());
    expect(state.loadingMore, isFalse);
  });

  test('loadMore() is a no-op when there is no next cursor', () async {
    final container = _containerWith(
      (request) => http.Response(_fixture('search_gguf.json'), 200),
    );
    await container.read(modelSearchControllerProvider.future);
    expect(
      container.read(modelSearchControllerProvider).value!.hasMore,
      isFalse,
    );

    await container.read(modelSearchControllerProvider.notifier).loadMore();

    // Still just the one page — no second request was made/applied.
    final state = container.read(modelSearchControllerProvider).value!;
    expect(state.items, hasLength(3));
  });

  test(
    'results are re-ranked so phone-suitable models sort above huge ones',
    () async {
      final container = _containerWith(
        (request) => http.Response(
          jsonEncode([
            {'id': 'org/Giant-70B-GGUF', 'downloads': 9999},
            {'id': 'org/Popular-Unknown-GGUF', 'downloads': 5000},
            {'id': 'org/Tiny-1B-GGUF', 'downloads': 10},
          ]),
          200,
        ),
      );
      final state = await container.read(modelSearchControllerProvider.future);
      // Small floats to the top despite fewest downloads; 70B sinks to bottom
      // despite the most downloads; unknown keeps its middle spot.
      expect(state.items.map((m) => m.id).toList(), [
        'org/Tiny-1B-GGUF',
        'org/Popular-Unknown-GGUF',
        'org/Giant-70B-GGUF',
      ]);
    },
  );

  test(
    'refresh() re-runs the current query without blanking the list',
    () async {
      final container = _containerWith(
        (request) => http.Response(_fixture('search_gguf.json'), 200),
      );
      await container.read(modelSearchControllerProvider.future);

      await container.read(modelSearchControllerProvider.notifier).refresh();

      final state = container.read(modelSearchControllerProvider).value!;
      expect(state.items, hasLength(3));
    },
  );
}
