/// Typed-failure-aware user messages (ADR-002: UI maps the shared failure
/// taxonomy to a message + recovery affordance). One place so the same
/// failure reads the same way on every models_hub screen.
library;

import 'app_failure.dart';

/// Renders any [AppFailure] leaf to a short, honest, user-facing sentence.
/// Exhaustive over the sealed taxonomy — a new failure type is a compile
/// error here until it's given a message.
String friendlyFailureMessage(AppFailure failure) {
  return switch (failure) {
    NetworkOfflineFailure() =>
      "You're offline — check your connection and try again.",
    NetworkRateLimitFailure() =>
      'Hugging Face is rate-limiting requests — wait a moment and retry.',
    NetworkGatedFailure() =>
      'This repo requires Hugging Face sign-in, which Dhruva doesn\'t '
          'support yet.',
    NetworkHttpFailure(:final statusCode) =>
      'Hugging Face returned an error (HTTP $statusCode).',
    NetworkUnknownFailure() =>
      "Couldn't read Hugging Face's response. Try again.",
    StorageInsufficientSpaceFailure(
      :final requiredBytes,
      :final availableBytes,
    ) =>
      'Not enough free space — need ${_formatBytes(requiredBytes)}, have '
          '${_formatBytes(availableBytes)} free.',
    StorageCorruptFileFailure() =>
      'The file failed an integrity check and was removed.',
    StorageNotFoundFailure() => 'That item is no longer available.',
    StorageIoFailure() => 'A storage error occurred.',
    StorageUnknownFailure() => 'A storage error occurred.',
    ValidationFailure(:final message) => message,
    UnknownFailure() => kGenericFailureMessage,
  };
}

/// Generic fallback used when we have nothing specific to say. Exposed so UI
/// (e.g. `ErrorStateView`) can avoid stacking it under an identical title.
const String kGenericFailureMessage = 'Something went wrong.';

/// For an arbitrary caught [Object] (e.g. from `AsyncValue.error`, which
/// isn't statically known to carry an [AppFailure]): the typed message when
/// it is one, a generic fallback otherwise.
String describeError(Object error) {
  return error is AppFailure
      ? friendlyFailureMessage(error)
      : kGenericFailureMessage;
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
