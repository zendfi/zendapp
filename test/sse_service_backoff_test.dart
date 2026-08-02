import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/services/sse_service.dart';

// Regression tests for Phase 3 (SSE transport reliability) fixes:
//   1. Backoff no longer ratchets forever once it hits the ceiling — it's
//      reset to the initial delay by the caller on every successful connect
//      (verified in sse_service.dart's `_connect()` by inspection; the pure
//      step function below is what actually computes the ratchet itself).
//   2. Reconnect delay carries "full jitter" (uniform random draw in
//      [0, delay]) instead of firing the timer at the exact backoff value,
//      so simultaneously-dropped clients don't reconnect in lockstep.
//
// `_scheduleReconnect()` itself isn't directly unit-testable without a live
// (or fake) network stream, so the backoff-doubling and jitter-drawing math
// it depends on were extracted into pure static functions
// (`SseService.nextBackoffDelay` / `SseService.jitteredReconnectDelay`) and
// are tested directly here.
void main() {
  group('SseService.nextBackoffDelay (Phase 3 SSE reliability)', () {
    const initial = Duration(seconds: 1);
    const max = Duration(seconds: 30);

    test('doubles from the initial delay', () {
      final next = SseService.nextBackoffDelay(initial, initial: initial, max: max);
      expect(next, const Duration(seconds: 2));
    });

    test('follows the documented 1 -> 2 -> 4 -> 8 -> 16 -> 30 (capped) progression', () {
      var delay = initial;
      final steps = <Duration>[];
      for (var i = 0; i < 6; i++) {
        delay = SseService.nextBackoffDelay(delay, initial: initial, max: max);
        steps.add(delay);
      }
      expect(steps, [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
        const Duration(seconds: 16),
        const Duration(seconds: 30), // clamped: 32 -> 30
        const Duration(seconds: 30), // clamped: 60 -> 30
      ]);
    });

    test('never exceeds the ceiling no matter how many times it is stepped', () {
      var delay = initial;
      for (var i = 0; i < 50; i++) {
        delay = SseService.nextBackoffDelay(delay, initial: initial, max: max);
        expect(delay.inSeconds, lessThanOrEqualTo(max.inSeconds));
      }
      expect(delay, max);
    });

    test('never drops below the initial delay even if given a smaller current value', () {
      final next = SseService.nextBackoffDelay(
        const Duration(milliseconds: 1),
        initial: initial,
        max: max,
      );
      expect(next.inSeconds, greaterThanOrEqualTo(initial.inSeconds));
    });
  });

  group('SseService.jitteredReconnectDelay (Phase 3 SSE reliability)', () {
    test('never exceeds the backoff ceiling passed in', () {
      final random = Random(1);
      const delay = Duration(seconds: 30);
      for (var i = 0; i < 200; i++) {
        final jittered = SseService.jitteredReconnectDelay(delay, random);
        expect(jittered.inMilliseconds, greaterThanOrEqualTo(0));
        expect(jittered.inMilliseconds, lessThanOrEqualTo(delay.inMilliseconds));
      }
    });

    test('produces a spread of values rather than always the exact delay '
        '(this is what fixes the reconnection-stampede problem)', () {
      final random = Random(42);
      const delay = Duration(seconds: 30);
      final draws = List.generate(
        100,
        (_) => SseService.jitteredReconnectDelay(delay, random).inMilliseconds,
      ).toSet();

      // With 100 draws over a wide range, we should see many distinct
      // values — if jitter were a no-op (always returning `delay`), this
      // set would have exactly 1 element.
      expect(draws.length, greaterThan(1));
    });

    test('a zero delay always jitters to zero (no negative or out-of-range draw)', () {
      final random = Random();
      final jittered = SseService.jitteredReconnectDelay(Duration.zero, random);
      expect(jittered, Duration.zero);
    });
  });
}
