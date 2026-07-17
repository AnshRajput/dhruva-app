import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/data/hf_api/models/model_license_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _fixture(String name) =>
    File('test/data/hf_api/fixtures/$name').readAsStringSync();

void main() {
  group('HfApiClient.searchGgufModels', () {
    test('parses a real search response shape', () async {
      final client = HfApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/models');
          expect(request.url.queryParameters['filter'], 'gguf');
          expect(request.url.queryParameters['search'], 'qwen');
          return http.Response(_fixture('search_gguf.json'), 200);
        }),
      );

      final result = await client.searchGgufModels(query: 'qwen');

      expect(result.items, hasLength(3));
      final first = result.items.first;
      expect(
        first.id,
        'HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive',
      );
      expect(first.likes, 2783);
      expect(first.downloads, 2328315);
      expect(first.pipelineTag, 'image-text-to-text');
      // license comes from the `license:*` tag; gated is unknown at search
      // time (only the per-repo endpoint carries `gated`).
      expect(first.license.license, 'apache-2.0');
      expect(first.license.gatedStatus, HfGatedStatus.none);

      final noLicenseTag = result.items.last;
      expect(noLicenseTag.license.license, isNull);
      expect(result.nextCursor, isNull);
    });

    test('parses a Link header into nextCursor', () async {
      final client = HfApiClient(
        client: MockClient((request) async {
          return http.Response(
            '[]',
            200,
            headers: {
              'link':
                  '<https://huggingface.co/api/models?filter=gguf&cursor=abc123>; rel="next"',
            },
          );
        }),
      );

      final result = await client.searchGgufModels(query: 'x');
      expect(result.nextCursor, 'abc123');
    });

    test('offline (SocketException) maps to NetworkOfflineFailure', () async {
      final client = HfApiClient(
        client: MockClient((request) async {
          throw const SocketException('no route to host');
        }),
      );

      await expectLater(
        () => client.searchGgufModels(query: 'x'),
        throwsA(isA<NetworkOfflineFailure>()),
      );
    });

    test('429 maps to NetworkRateLimitFailure', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async => http.Response('rate limited', 429),
        ),
      );

      await expectLater(
        () => client.searchGgufModels(query: 'x'),
        throwsA(isA<NetworkRateLimitFailure>()),
      );
    });

    test('500 maps to NetworkHttpFailure with statusCode', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async => http.Response('server error', 500),
        ),
      );

      await expectLater(
        () => client.searchGgufModels(query: 'x'),
        throwsA(
          isA<NetworkHttpFailure>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test('malformed JSON maps to NetworkUnknownFailure', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async => http.Response('not json{{{', 200),
        ),
      );

      await expectLater(
        () => client.searchGgufModels(query: 'x'),
        throwsA(isA<NetworkUnknownFailure>()),
      );
    });

    test('empty results array parses to an empty list, no crash', () async {
      final client = HfApiClient(
        client: MockClient((request) async => http.Response('[]', 200)),
      );

      final result = await client.searchGgufModels(query: 'no-such-model-xyz');

      expect(result.items, isEmpty);
      expect(result.nextCursor, isNull);
    });
  });

  group('HfApiClient.getRepoFiles', () {
    test('parses the tree response and extracts lfs sha256', () async {
      final client = HfApiClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mmproj')) {
            return http.Response(_fixture('mmproj_tree.json'), 200);
          }
          return http.Response(_fixture('repo_tree.json'), 200);
        }),
      );

      final files = await client.getRepoFiles(
        'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      );

      final withHash = files.firstWhere((f) => f.path.endsWith('IQ3_M.gguf'));
      expect(withHash.sizeBytes, 776664320);
      expect(
        withHash.sha256,
        'aebd579aa34bde75426b7e3b786b089bc366f16da19e8aa60945d27f77e780f0',
      );

      final withoutHash = files.firstWhere((f) => f.path.endsWith('Q2_K.gguf'));
      expect(withoutHash.sha256, isNull);

      // The "mmproj" directory entry was walked, not returned as a file.
      expect(files.any((f) => f.path == 'mmproj'), isFalse);
      final subfolderFile = files.firstWhere(
        (f) => f.path == 'mmproj/mmproj-Q8_0.gguf',
      );
      expect(subfolderFile.sizeBytes, 500000000);
    });

    test(
      'quantVariantsFrom filters to files with a recognized quant token',
      () async {
        final client = HfApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/mmproj')) {
              return http.Response(_fixture('mmproj_tree.json'), 200);
            }
            return http.Response(_fixture('repo_tree.json'), 200);
          }),
        );
        final files = await client.getRepoFiles(
          'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
        );
        final variants = client.quantVariantsFrom(files);

        // 8 quantized files in the fixture + 1 mmproj file = 9.
        expect(variants, hasLength(9));
        expect(variants.map((v) => v.label), contains('Q4_K_M'));
      },
    );

    test('404 on a repo maps to NetworkHttpFailure', () async {
      final client = HfApiClient(
        client: MockClient((request) async => http.Response('not found', 404)),
      );
      await expectLater(
        () => client.getRepoFiles('nonexistent/repo'),
        throwsA(
          isA<NetworkHttpFailure>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test(
      'an lfs.oid of the wrong length is treated as absent, not misread as sha256 '
      '(attack #7: hostile tree entries)',
      () async {
        final client = HfApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode([
                {
                  'type': 'file',
                  'path': 'weird-Q4_K_M.gguf',
                  'size': 100,
                  'lfs': {'oid': 'not-a-real-sha256'},
                },
              ]),
              200,
            ),
          ),
        );
        final files = await client.getRepoFiles('x/y');
        expect(files.single.sha256, isNull);
      },
    );

    test(
      'a tree entry missing "path" entirely does not crash the walk',
      () async {
        final client = HfApiClient(
          client: MockClient(
            (request) async => http.Response(
              jsonEncode([
                {'type': 'file', 'size': 100},
              ]),
              200,
            ),
          ),
        );
        final files = await client.getRepoFiles('x/y');
        expect(files.single.path, '');
      },
    );
  });

  group('HfApiClient.getModelLicenseInfo', () {
    test('open repo: license + gated:false', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async =>
              http.Response(_fixture('model_info_open.json'), 200),
        ),
      );
      final info = await client.getModelLicenseInfo(
        'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      );
      expect(info.license, 'apache-2.0');
      expect(info.gatedStatus, HfGatedStatus.none);
      expect(info.requiresAuth, isFalse);
    });

    test('gated repo: license + gated:"manual"', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async =>
              http.Response(_fixture('model_info_gated.json'), 200),
        ),
      );
      final info = await client.getModelLicenseInfo('meta-llama/Llama-2-7b-hf');
      expect(info.license, 'llama2');
      expect(info.gatedStatus, HfGatedStatus.manual);
      expect(info.requiresAuth, isTrue);
    });

    test('401 on a gated repo maps to NetworkGatedFailure', () async {
      final client = HfApiClient(
        client: MockClient(
          (request) async => http.Response('unauthorized', 401),
        ),
      );
      await expectLater(
        () => client.getModelLicenseInfo('meta-llama/Llama-2-7b-hf'),
        throwsA(isA<NetworkGatedFailure>()),
      );
    });

    test('403 also maps to NetworkGatedFailure', () async {
      final client = HfApiClient(
        client: MockClient((request) async => http.Response('forbidden', 403)),
      );
      await expectLater(
        () => client.getModelLicenseInfo('meta-llama/Llama-2-7b-hf'),
        throwsA(isA<NetworkGatedFailure>()),
      );
    });
  });

  group('HfApiClient.resolveDownloadUrl', () {
    test('builds the canonical resolve/main URL', () {
      final client = HfApiClient();
      final url = client.resolveDownloadUrl(
        'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
        'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      );
      expect(
        url.toString(),
        'https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/'
        'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      );
    });

    test(
      'a file path with URL-hostile characters (spaces, unicode) round-trips '
      'through percent-encoding (attack #7)',
      () {
        final client = HfApiClient();
        final url = client.resolveDownloadUrl(
          'org/repo name',
          'sub dir/模型 Q4_K_M.gguf',
        );
        // The encoded URL must be parseable and must decode back to the
        // exact same path segments — no silent corruption/truncation.
        final rebuilt = Uri.parse(url.toString());
        expect(rebuilt.pathSegments, [
          'org',
          'repo name',
          'resolve',
          'main',
          'sub dir',
          '模型 Q4_K_M.gguf',
        ]);
      },
    );

    test('a normal org/repo id with its expected single slash is preserved as '
        'two path segments, not collapsed or double-encoded', () {
      final client = HfApiClient();
      final url = client.resolveDownloadUrl(
        'meta-llama/Llama-3.2-1B',
        'model.gguf',
      );
      expect(Uri.parse(url.toString()).pathSegments, [
        'meta-llama',
        'Llama-3.2-1B',
        'resolve',
        'main',
        'model.gguf',
      ]);
    });
  });

  test('json decode helper is exercised via a non-list search body', () async {
    final client = HfApiClient(
      client: MockClient(
        (request) async => http.Response(jsonEncode({'not': 'a list'}), 200),
      ),
    );
    await expectLater(
      () => client.searchGgufModels(query: 'x'),
      throwsA(isA<NetworkUnknownFailure>()),
    );
  });
}
