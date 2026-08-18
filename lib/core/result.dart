// ==================== Result ==================== //
//
// An operation either produced a value or produced an [AppError].
//
// Most of this app's work is I/O against a server that is frequently
// unreachable, slow, or running a workflow that fails halfway. Modelling
// that in the return type instead of in thrown exceptions means a caller
// cannot forget the failure path - it has to unwrap the value to use it.
//
// Reserve throwing for genuine programmer error (bad argument, broken
// invariant). Anything the user could plausibly cause is a Result.

import 'package:flutter/foundation.dart';

import 'package:sd_companion/core/app_error.dart';

@immutable
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(AppError error) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The value, or null when this is a failure.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// The error, or null when this succeeded.
  AppError? get errorOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final error) => error,
      };

  /// The value, or [fallback] when this is a failure.
  T orElse(T fallback) => valueOrNull ?? fallback;

  /// Collapses both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(AppError error) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final error) => onErr(error),
      };

  /// Transforms a success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok<R>(transform(value)),
        Err<T>(:final error) => Err<R>(error),
      };

  /// Chains another fallible step onto a success.
  Result<R> flatMap<R>(Result<R> Function(T value) next) => switch (this) {
        Ok<T>(:final value) => next(value),
        Err<T>(:final error) => Err<R>(error),
      };
}

@immutable
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T> extends Result<T> {
  final AppError error;
  const Err(this.error);

  @override
  bool operator ==(Object other) => other is Err<T> && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}

/// Runs [body] and converts anything it throws into a typed [Err].
///
/// This is the single place an I/O boundary crosses from exceptions into
/// Results, so the mapping stays consistent everywhere.
Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } catch (error, stack) {
    return Err(describeError(error, stack));
  }
}

/// Synchronous [guard].
Result<T> guardSync<T>(T Function() body) {
  try {
    return Ok(body());
  } catch (error, stack) {
    return Err(describeError(error, stack));
  }
}
