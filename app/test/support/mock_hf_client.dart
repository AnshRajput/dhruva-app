/// Test transport for the dio-based [HfApiClient].
///
/// The suite still authors fake responses with `package:http`'s `MockClient`
/// (and throws `SocketException` for the offline case) — the ergonomics we had
/// before the dio migration. This tiny custom [HttpClientAdapter] feeds an
/// `http.Client` into dio, so a test's `MockClient((request) async {...})`
/// body stays byte-for-byte the same; only the wrapper changes from
/// `HfApiClient(client: MockClient(...))` to `mockHfClient(MockClient(...))`.
library;

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

/// An [HfApiClient] whose dio transport delegates to [inner] (a `MockClient`).
/// Retries are disabled by default so a deliberately-failing responder
/// resolves in one shot (retry-specific tests pass their own [maxRetries]).
HfApiClient mockHfClient(
  http.Client inner, {
  Uri? baseUrl,
  int maxRetries = 0,
  Duration retryBackoff = Duration.zero,
}) {
  final dio = Dio()..httpClientAdapter = _HttpClientAdapterBridge(inner);
  return HfApiClient(
    dio: dio,
    baseUrl: baseUrl,
    maxRetries: maxRetries,
    retryBackoff: retryBackoff,
  );
}

class _HttpClientAdapterBridge implements HttpClientAdapter {
  final http.Client _inner;
  _HttpClientAdapterBridge(this._inner);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final http.Response res;
    try {
      res = await _inner
          .send(_toHttpRequest(options))
          .then(http.Response.fromStream);
    } on SocketException catch (e) {
      // Surface as a dio connection error so HfApiClient maps it to
      // NetworkOfflineFailure (mirrors the old on-SocketException path).
      throw DioException.connectionError(
        requestOptions: options,
        reason: e.message,
        error: e,
      );
    }
    return ResponseBody.fromString(
      res.body,
      res.statusCode,
      headers: res.headers.map((k, v) => MapEntry(k, [v])),
    );
  }

  http.Request _toHttpRequest(RequestOptions options) {
    final req = http.Request(options.method, options.uri);
    options.headers.forEach((k, v) => req.headers[k] = '$v');
    return req;
  }

  @override
  void close({bool force = false}) => _inner.close();
}
