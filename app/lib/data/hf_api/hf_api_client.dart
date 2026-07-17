import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../core/failures/app_failure.dart';
import 'models/hf_model_summary.dart';
import 'models/hf_repo_file.dart';
import 'models/hf_search_result.dart';
import 'models/model_license_info.dart';
import 'models/quant_variant.dart';
import 'quant_parser.dart';

/// Hugging Face Hub API client. Endpoints + response shapes verified with
/// real curl calls — see orchestra/research/hf-api.md. Public/unauthenticated
/// only (no HF token support yet — gated repos surface as
/// [NetworkGatedFailure] rather than being downloadable).
final class HfApiClient {
  final http.Client _client;
  final Uri _base;

  HfApiClient({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _base = baseUrl ?? Uri.parse('https://huggingface.co');

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
    final decoded = _decodeJson(response.body);
    if (decoded is! List) {
      throw const NetworkUnknownFailure('search response was not a JSON array');
    }
    final items = decoded
        .cast<Map<String, dynamic>>()
        .map(_summaryFromJson)
        .toList(growable: false);
    return HfSearchResult(
      items: items,
      nextCursor: _nextCursorFrom(response.headers['link']),
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
    final decoded = _decodeJson(response.body);
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
    final decoded = _decodeJson(response.body);
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
  /// GGUF quant token.
  List<QuantVariant> quantVariantsFrom(List<HfRepoFile> files) {
    final variants = <QuantVariant>[];
    for (final file in files) {
      final label = extractQuantVariant(file.path);
      if (label != null) variants.add(QuantVariant(label: label, file: file));
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

  Future<http.Response> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri);
    } on SocketException catch (e) {
      throw NetworkOfflineFailure('no network connection', cause: e);
    } on http.ClientException catch (e) {
      throw NetworkOfflineFailure(
        'request failed to reach the server',
        cause: e,
      );
    }
    final status = response.statusCode;
    if (status == 429) {
      throw NetworkRateLimitFailure(
        'rate limited by huggingface.co',
        cause: status,
      );
    }
    if (status == 401 || status == 403) {
      throw NetworkGatedFailure(
        'this repo is gated and requires authentication',
        cause: status,
      );
    }
    if (status < 200 || status >= 300) {
      throw NetworkHttpFailure(
        'huggingface.co returned HTTP $status',
        statusCode: status,
      );
    }
    return response;
  }

  void close() => _client.close();
}
