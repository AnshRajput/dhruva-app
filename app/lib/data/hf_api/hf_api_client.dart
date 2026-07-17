import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';

import '../../core/failures/app_failure.dart';
import 'models/hf_model_summary.dart';
import 'models/hf_repo_file.dart';
import 'models/hf_search_result.dart';
import 'models/model_license_info.dart';
import 'models/quant_variant.dart';
import 'quant_parser.dart';
import 'vision_pairing.dart';

/// Hugging Face Hub API client. Endpoints + response shapes verified with
/// real curl calls — see orchestra/research/hf-api.md. Public/unauthenticated
/// only (no HF token support yet — gated repos surface as
/// [NetworkGatedFailure] rather than being downloadable).
///
/// Transport is `dio` (migrated off `package:http`): per-request connect +
/// receive timeouts and a light retry on transient network errors (mobile
/// links drop mid-request — a real connection-abort was hit on-device). The
/// public API and the typed [AppFailure] mapping are unchanged; only the
/// wire layer moved. Model file DOWNLOADS still go through
/// `background_downloader`, not dio.
final class HfApiClient {
  final Dio _dio;
  final Uri _base;
  final int _maxRetries;
  final Duration _retryBackoff;

  HfApiClient({
    Dio? dio,
    Uri? baseUrl,
    int maxRetries = 2,
    Duration retryBackoff = const Duration(milliseconds: 250),
  }) : _dio = dio ?? _defaultDio(),
       _base = baseUrl ?? Uri.parse('https://huggingface.co'),
       _maxRetries = maxRetries,
       _retryBackoff = retryBackoff;

  static Dio _defaultDio() => Dio(
    BaseOptions(
      connectTimeout: requestTimeout,
      receiveTimeout: requestTimeout,
      // Raw body: we decode JSON ourselves (same as the old http path) so a
      // malformed body surfaces as [NetworkUnknownFailure], not a dio parse
      // error, and the exact bytes reach [_decodeJson].
      responseType: ResponseType.plain,
    ),
  );

  /// `GET /api/models?filter=gguf&search=...&sort=...&limit=...[&cursor=...]`
  Future<HfSearchResult> searchGgufModels({
    required String query,
    String sort = 'downloads',
    int limit = 20,
    String? cursor,
  }) async {
    final uri = _base.replace(
      path: '/api/models',
      queryParameters: {
        'filter': 'gguf',
        'search': query,
        'sort': sort,
        'limit': '$limit',
        'cursor': ?cursor,
      },
    );
    final response = await _get(uri);
    final decoded = _decodeJson(response.data ?? '');
    if (decoded is! List) {
      throw const NetworkUnknownFailure('search response was not a JSON array');
    }
    final items = decoded
        .cast<Map<String, dynamic>>()
        .map(_summaryFromJson)
        .toList(growable: false);
    return HfSearchResult(
      items: items,
      nextCursor: _nextCursorFrom(response.headers.value('link')),
    );
  }

  /// `GET /api/models/{repo}/tree/main` — recurses into subfolder entries
  /// (mmproj files often live under a subfolder) by walking each
  /// `type: "directory"` entry's own `/tree/main/{path}` listing.
  Future<List<HfRepoFile>> getRepoFiles(String repoId) async {
    final files = <HfRepoFile>[];
    await _walkTree(repoId, null, files);
    return files;
  }

  Future<void> _walkTree(
    String repoId,
    String? subPath,
    List<HfRepoFile> out,
  ) async {
    final path = subPath == null
        ? '/api/models/$repoId/tree/main'
        : '/api/models/$repoId/tree/main/$subPath';
    final response = await _get(_base.replace(path: path));
    final decoded = _decodeJson(response.data ?? '');
    if (decoded is! List) {
      throw const NetworkUnknownFailure('tree response was not a JSON array');
    }
    for (final raw in decoded.cast<Map<String, dynamic>>()) {
      final type = raw['type'] as String?;
      final entryPath = raw['path'] as String? ?? '';
      if (type == 'directory') {
        await _walkTree(repoId, entryPath, out);
        continue;
      }
      final lfs = raw['lfs'] as Map<String, dynamic>?;
      out.add(
        HfRepoFile(
          path: entryPath,
          sizeBytes: (raw['size'] as num?)?.toInt() ?? 0,
          sha256: _sha256FromLfs(lfs),
        ),
      );
    }
  }

  /// `lfs.oid` is a plain hex sha256 in the verified responses (no
  /// "sha256:" prefix observed) — pass through as-is; guard length so a
  /// non-sha256 oid scheme doesn't silently masquerade as one.
  String? _sha256FromLfs(Map<String, dynamic>? lfs) {
    final oid = lfs?['oid'] as String?;
    if (oid == null) return null;
    final hex = oid.startsWith('sha256:') ? oid.substring(7) : oid;
    return hex.length == 64 ? hex : null;
  }

  /// `GET /api/models/{repo}` — authoritative license + gating status for a
  /// single repo (the search endpoint doesn't carry `gated`).
  Future<ModelLicenseInfo> getModelLicenseInfo(String repoId) async {
    final response = await _get(_base.replace(path: '/api/models/$repoId'));
    final decoded = _decodeJson(response.data ?? '');
    if (decoded is! Map<String, dynamic>) {
      throw const NetworkUnknownFailure(
        'model info response was not a JSON object',
      );
    }
    return _licenseFromJson(decoded);
  }

  /// Non-network, pure URL builder: `/{repo}/resolve/main/{file}`. Follows
  /// the redirect itself when downloaded (background_downloader handles
  /// that); this just builds the canonical entry point.
  Uri resolveDownloadUrl(String repoId, String filePath) {
    return _base.replace(path: '/$repoId/resolve/main/$filePath');
  }

  /// Filters [files] down to entries whose filename carries a recognized
  /// GGUF quant token — excluding the mmproj projector files themselves
  /// (see [isMmprojFile]; a projector isn't a user-selectable download, it
  /// rides along automatically with its paired model, see
  /// `download_actions_controller.dart`'s `enqueueVisionQuant`). Each
  /// remaining quant is paired with its best-matched mmproj projector, if
  /// this repo has any (see [matchMmprojFor]) — that pairing is what marks
  /// [QuantVariant.isVision].
  List<QuantVariant> quantVariantsFrom(List<HfRepoFile> files) {
    final mmprojFiles = files.where((f) => isMmprojFile(f.path)).toList();
    final variants = <QuantVariant>[];
    for (final file in files) {
      if (isMmprojFile(file.path)) continue;
      final label = extractQuantVariant(file.path);
      if (label == null) continue;
      variants.add(
        QuantVariant(
          label: label,
          file: file,
          mmprojFile: matchMmprojFor(file, mmprojFiles),
        ),
      );
    }
    return variants;
  }

  HfModelSummary _summaryFromJson(Map<String, dynamic> json) {
    final tags = (json['tags'] as List?)?.cast<String>() ?? const [];
    return HfModelSummary(
      id: json['id'] as String? ?? '',
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      tags: tags,
      pipelineTag: json['pipeline_tag'] as String?,
      // Search results don't carry `gated` (only the per-repo endpoint
      // does) — best-effort license from the `license:*` tag, gating
      // unknown until `getModelLicenseInfo` is called for this repo.
      license: ModelLicenseInfo(
        license: _licenseTagFrom(tags),
        gatedStatus: HfGatedStatus.none,
      ),
    );
  }

  ModelLicenseInfo _licenseFromJson(Map<String, dynamic> json) {
    final cardData = json['cardData'] as Map<String, dynamic>?;
    final tags = (json['tags'] as List?)?.cast<String>() ?? const [];
    final license =
        cardData?['license'] as String? ??
        json['license'] as String? ??
        _licenseTagFrom(tags);
    return ModelLicenseInfo(
      license: license,
      gatedStatus: _gatedStatusFrom(json['gated']),
    );
  }

  String? _licenseTagFrom(List<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith('license:')) return tag.substring('license:'.length);
    }
    return null;
  }

  HfGatedStatus _gatedStatusFrom(Object? gated) {
    if (gated == 'manual') return HfGatedStatus.manual;
    if (gated == 'auto') return HfGatedStatus.auto;
    // Some legacy responses use `gated: true` instead of a string reason.
    if (gated == true) return HfGatedStatus.manual;
    return HfGatedStatus.none;
  }

  String? _nextCursorFrom(String? linkHeader) {
    if (linkHeader == null) return null;
    // RFC 5988: `<url>; rel="next", <url>; rel="prev"`.
    for (final part in linkHeader.split(',')) {
      if (!part.contains('rel="next"')) continue;
      final urlMatch = RegExp(r'<([^>]+)>').firstMatch(part);
      final url = urlMatch?.group(1);
      if (url == null) return null;
      return Uri.parse(url).queryParameters['cursor'];
    }
    return null;
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      throw NetworkUnknownFailure('malformed JSON response', cause: e);
    }
  }

  /// Ceiling for any single metadata request. Without it, a hung connection
  /// (misconfigured network, captive portal, missing permission) spins the UI
  /// forever instead of reaching the typed error state.
  static const requestTimeout = Duration(seconds: 15);

  Future<Response<String>> _get(Uri uri) async {
    // Outer hard ceiling (a Dart timer, so `fakeAsync` can drive it, and a
    // belt over dio's own receiveTimeout for a truly hung socket). Never
    // retried — a request that blows the whole ceiling is treated as offline.
    for (var attempt = 0; ; attempt++) {
      try {
        return await _dio.getUri<String>(uri).timeout(requestTimeout);
      } on TimeoutException catch (e) {
        throw NetworkOfflineFailure(
          'request timed out after ${requestTimeout.inSeconds}s',
          cause: e,
        );
      } on DioException catch (e) {
        if (_isTransient(e) && attempt < _maxRetries) {
          await Future<void>.delayed(_retryBackoff * (attempt + 1));
          continue;
        }
        throw _mapDioException(e);
      }
    }
  }

  /// Only connection-level failures are worth retrying — a mid-request abort,
  /// a dropped socket, or a per-request timeout on a flaky mobile link. A
  /// [DioExceptionType.badResponse] (429/gated/http) is a deterministic server
  /// answer and is surfaced immediately.
  bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  AppFailure _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkOfflineFailure(
          'request timed out after ${requestTimeout.inSeconds}s',
          cause: e,
        );
      case DioExceptionType.connectionError:
        return NetworkOfflineFailure('no network connection', cause: e);
      case DioExceptionType.badResponse:
        return _mapStatus(e.response?.statusCode ?? 0);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        // A raw SocketException surfacing as `unknown` is still an offline
        // condition (e.g. thrown by a custom adapter or DNS failure).
        if (e.error is SocketException) {
          return NetworkOfflineFailure('no network connection', cause: e);
        }
        return NetworkUnknownFailure(
          'request to huggingface.co failed',
          cause: e,
        );
    }
  }

  AppFailure _mapStatus(int status) {
    if (status == 429) {
      return NetworkRateLimitFailure(
        'rate limited by huggingface.co',
        cause: status,
      );
    }
    if (status == 401 || status == 403) {
      return NetworkGatedFailure(
        'this repo is gated and requires authentication',
        cause: status,
      );
    }
    return NetworkHttpFailure(
      'huggingface.co returned HTTP $status',
      statusCode: status,
    );
  }

  void close() => _dio.close();
}
