/// Shared failure taxonomy (ADR-002 §Error taxonomy), for every layer below
/// `engine_bindings/` (which has its own `EngineFailure` tree — see
/// `engine_bindings/engine_service.dart`). Repositories map lower-layer
/// exceptions (`SocketException`, drift errors, `FileSystemException`, ...)
/// into these; UI maps a failure to a message + recovery affordance.
///
/// Plain sealed classes (not freezed) to mirror the precedent set by
/// `EngineFailure` in Loop 2 — freezed is reserved for data models in this
/// codebase (see `data/hf_api/models/`).
library;

/// Root of the shared taxonomy. Never thrown directly — always one of the
/// three branches below, or `EngineFailure` for engine-layer errors.
sealed class AppFailure implements Exception {
  final String message;
  final Object? cause;
  const AppFailure(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// hf_api / download errors.
sealed class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.cause});
}

/// No connectivity, or the request never reached a server (DNS failure,
/// connection refused, timeout before any response).
final class NetworkOfflineFailure extends NetworkFailure {
  const NetworkOfflineFailure(super.message, {super.cause});
}

/// A non-2xx HTTP response that isn't more specifically classified below.
final class NetworkHttpFailure extends NetworkFailure {
  final int statusCode;
  const NetworkHttpFailure(
    super.message, {
    required this.statusCode,
    super.cause,
  });
}

/// HTTP 429 — caller should back off before retrying.
final class NetworkRateLimitFailure extends NetworkFailure {
  const NetworkRateLimitFailure(super.message, {super.cause});
}

/// HTTP 401/403 on a `gated` repo — the user needs to authenticate with HF
/// and accept the repo's license before this resource is reachable.
final class NetworkGatedFailure extends NetworkFailure {
  const NetworkGatedFailure(super.message, {super.cause});
}

/// Response didn't parse into the shape we expect (HF API drift).
final class NetworkUnknownFailure extends NetworkFailure {
  const NetworkUnknownFailure(super.message, {super.cause});
}

/// drift / filesystem errors.
sealed class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause});
}

/// Not enough free space for the requested write. Always carries the byte
/// counts so the UI can show "need 986 MB, have 400 MB free".
final class StorageInsufficientSpaceFailure extends StorageFailure {
  final int requiredBytes;
  final int availableBytes;
  const StorageInsufficientSpaceFailure(
    super.message, {
    required this.requiredBytes,
    required this.availableBytes,
    super.cause,
  });
}

/// A read/write/delete on the filesystem or db failed.
final class StorageIoFailure extends StorageFailure {
  const StorageIoFailure(super.message, {super.cause});
}

/// Looked-up file/row doesn't exist.
final class StorageNotFoundFailure extends StorageFailure {
  const StorageNotFoundFailure(super.message, {super.cause});
}

/// A downloaded/imported file failed integrity validation (size mismatch,
/// checksum mismatch, or bad GGUF magic bytes).
final class StorageCorruptFileFailure extends StorageFailure {
  const StorageCorruptFileFailure(super.message, {super.cause});
}

final class StorageUnknownFailure extends StorageFailure {
  const StorageUnknownFailure(super.message, {super.cause});
}

/// Bad user/caller input, caught before any I/O.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause});
}

/// Last resort. Always carries the original `cause`.
final class UnknownFailure extends AppFailure {
  const UnknownFailure(super.message, {super.cause});
}
