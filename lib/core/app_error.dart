// ==================== App Error ==================== //
//
// One error taxonomy for the whole app.
//
// Before this, failures arrived as a mix of `Exception`, `StateError`,
// `BackendException`, `ComfyWorkflowParseException` and
// `ComfyGalleryUnavailableException`, so every call site either caught
// broadly and stringified, or missed a case. A sealed hierarchy means the
// analyzer can prove a handler is exhaustive, and the UI can decide how to
// present a failure from its *kind* rather than by matching on message text.

import 'package:flutter/foundation.dart';

@immutable
sealed class AppError {
  /// Message safe to show a person. Says what went wrong and, where it can,
  /// what to do about it.
  final String message;

  /// The underlying exception, kept for logs - never shown to the user.
  final Object? cause;

  const AppError(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// The server could not be reached at all: wrong address, not running,
/// no route, DNS failure.
final class UnreachableError extends AppError {
  const UnreachableError(super.message, {super.cause});
}

/// The server was reached but took too long.
final class TimeoutError extends AppError {
  const TimeoutError(super.message, {super.cause});
}

/// The server answered, but with a failure status or an unusable body.
final class ServerError extends AppError {
  final int? statusCode;
  const ServerError(super.message, {this.statusCode, super.cause});
}

/// The request was rejected before execution - a malformed workflow, a
/// missing prompt, a node the server doesn't know about.
final class ValidationError extends AppError {
  const ValidationError(super.message, {super.cause});
}

/// Execution started and then failed inside the engine (e.g. a ComfyUI node
/// raised). Distinct from [ValidationError] because the graph was accepted.
final class ExecutionError extends AppError {
  /// Which node failed, when the engine tells us.
  final String? nodeId;
  const ExecutionError(super.message, {this.nodeId, super.cause});
}

/// The active engine genuinely cannot do this - asking Forge for a ComfyUI
/// workflow, or ComfyUI for a LoRA inventory. Callers should be gating on
/// EngineCapabilities and treating this as a bug backstop.
final class CapabilityError extends AppError {
  const CapabilityError(super.message, {super.cause});
}

/// Reading or writing local persistence failed.
final class StorageError extends AppError {
  const StorageError(super.message, {super.cause});
}

/// The user stopped it. Not a failure - handlers should usually stay quiet.
final class CancelledError extends AppError {
  const CancelledError([super.message = 'Cancelled', Object? cause])
      : super(cause: cause);
}

/// Nothing else fit. Keep rare; prefer adding a case above.
final class UnknownError extends AppError {
  const UnknownError(super.message, {super.cause});
}

/// Maps a thrown object onto the taxonomy, so `catch (e)` at an I/O boundary
/// can produce a typed error without every call site re-implementing the
/// same guesswork.
AppError describeError(Object error, [StackTrace? stack]) {
  if (error is AppError) return error;

  final text = error.toString();
  final lower = text.toLowerCase();

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return TimeoutError('The server took too long to respond.', cause: error);
  }
  if (lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return UnreachableError(
      'Could not reach the server. Check that it is running and the address is right.',
      cause: error,
    );
  }
  if (lower.contains('formatexception') || lower.contains('unexpected character')) {
    return ServerError('The server sent a response the app could not read.', cause: error);
  }
  return UnknownError(text, cause: error);
}
