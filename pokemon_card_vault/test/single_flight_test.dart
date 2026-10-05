import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/utils/single_flight.dart';

void main() {
  test('concurrent consumers share one request and the same future', () async {
    final flight = SingleFlight<int>();
    final pending = Completer<int>();
    var calls = 0;
    Future<int> load() {
      calls++;
      return pending.future;
    }

    final first = flight.run(load);
    final second = flight.run(load);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    pending.complete(98);
    expect(await first, 98);
    expect(await second, 98);
  });

  test('a completed request is not reused as stale cache', () async {
    final flight = SingleFlight<int>();
    var calls = 0;
    Future<int> load() async => ++calls;
    expect(await flight.run(load), 1);
    expect(await flight.run(load), 2);
  });

  test('a failed request does not prevent a retry', () async {
    final flight = SingleFlight<int>();
    await expectLater(
      flight.run(() async => throw StateError('test-only failure')),
      throwsStateError,
    );
    expect(await flight.run(() async => 42), 42);
  });

  test('a synchronous loader failure also releases the in-flight slot',
      () async {
    final flight = SingleFlight<int>();
    await expectLater(
      flight.run(() => throw StateError('test-only failure')),
      throwsStateError,
    );
    expect(await flight.run(() async => 7), 7);
  });
}
