// Covers the Result type and the exception->AppError mapping that every
// I/O boundary relies on. If this drifts, failures start arriving at the UI
// as untyped strings again, which is the thing Result exists to prevent.

import 'package:flutter_test/flutter_test.dart';

import 'package:sd_companion/core/app_error.dart';
import 'package:sd_companion/core/result.dart';

void main() {
  group('Result', () {
    test('Ok carries its value and reports success', () {
      const result = Result<int>.ok(42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.errorOrNull, isNull);
    });

    test('Err carries its error and reports failure', () {
      const error = TimeoutError('too slow');
      const result = Result<int>.err(error);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.errorOrNull, same(error));
    });

    test('orElse substitutes only on failure', () {
      expect(const Result<int>.ok(1).orElse(99), 1);
      expect(const Result<int>.err(UnknownError('x')).orElse(99), 99);
    });

    test('fold collapses both branches', () {
      String describe(Result<int> r) =>
          r.fold((v) => 'ok:$v', (e) => 'err:${e.message}');

      expect(describe(const Result.ok(7)), 'ok:7');
      expect(describe(const Result.err(ServerError('boom'))), 'err:boom');
    });

    test('map transforms success and passes failure through untouched', () {
      expect(const Result<int>.ok(2).map((v) => v * 3).valueOrNull, 6);

      const error = ValidationError('bad');
      final mapped = const Result<int>.err(error).map((v) => v * 3);
      expect(mapped.errorOrNull, same(error));
    });

    test('flatMap chains fallible steps and short-circuits on failure', () {
      Result<int> double_(int v) => Result.ok(v * 2);
      Result<int> fail(int _) => const Result.err(StorageError('nope'));

      expect(const Result<int>.ok(3).flatMap(double_).valueOrNull, 6);
      expect(const Result<int>.ok(3).flatMap(fail).isErr, isTrue);
      expect(
        const Result<int>.err(UnknownError('first')).flatMap(double_).errorOrNull?.message,
        'first',
        reason: 'the original error must survive, not be replaced',
      );
    });

    test('equality is by contained value, so results can be compared in tests', () {
      expect(const Result<int>.ok(1), const Result<int>.ok(1));
      expect(const Result<int>.ok(1), isNot(const Result<int>.ok(2)));
    });
  });

  group('guard', () {
    test('wraps a returned value in Ok', () async {
      final result = await guard(() async => 'fine');
      expect(result.valueOrNull, 'fine');
    });

    test('converts a thrown object into a typed Err instead of rethrowing', () async {
      final result = await guard<String>(() async => throw StateError('kaboom'));
      expect(result.isErr, isTrue);
      expect(result.errorOrNull, isA<UnknownError>());
    });

    test('passes an AppError through unchanged rather than re-wrapping it', () async {
      const original = ValidationError('already typed');
      final result = await guard<String>(() async => throw original);
      expect(result.errorOrNull, same(original));
    });

    test('guardSync behaves the same for synchronous work', () {
      expect(guardSync(() => 5).valueOrNull, 5);
      expect(guardSync<int>(() => throw Exception('x')).isErr, isTrue);
    });
  });

  group('describeError', () {
    test('recognises timeouts', () {
      expect(describeError(Exception('Connection timed out')), isA<TimeoutError>());
    });

    test('recognises an unreachable host', () {
      expect(
        describeError(Exception('SocketException: connection refused')),
        isA<UnreachableError>(),
      );
      expect(
        describeError(Exception('Failed host lookup: nope.local')),
        isA<UnreachableError>(),
      );
    });

    test('recognises an unreadable response body', () {
      expect(
        describeError(const FormatException('unexpected character')),
        isA<ServerError>(),
      );
    });

    test('falls back to UnknownError for anything unrecognised', () {
      expect(describeError(Exception('something novel')), isA<UnknownError>());
    });
  });
}
