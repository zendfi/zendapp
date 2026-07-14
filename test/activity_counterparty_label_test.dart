// Regression test for the "raw UUID instead of @zendtag" bug: ensures
// ActivityCounterparty.displayLabel/initialLetter always prefer a real
// identity field and never surface a bare full UUID.

import 'package:flutter_test/flutter_test.dart';
import 'package:zendapp/src/models/activity_edge.dart';

void main() {
  group('ActivityCounterparty.displayLabel', () {
    test('prefers @zendtag when present', () {
      const cp = ActivityCounterparty(
        kind: 'user',
        id: '3328eed1-06c2-4a1a-9b7f-1234567890ab',
        zendtag: 'omooba',
        displayName: 'Omooba',
      );
      expect(cp.displayLabel, '@omooba');
    });

    test('falls back to displayName when zendtag is missing', () {
      const cp = ActivityCounterparty(
        kind: 'user',
        id: '3328eed1-06c2-4a1a-9b7f-1234567890ab',
        displayName: 'Omooba',
      );
      expect(cp.displayLabel, 'Omooba');
    });

    test('falls back to poolName for a pool counterparty', () {
      const cp = ActivityCounterparty(
        kind: 'pool',
        id: '3328eed1-06c2-4a1a-9b7f-1234567890ab',
        poolName: 'Rent Fund',
      );
      expect(cp.displayLabel, 'Rent Fund');
    });

    test('never renders a bare full UUID — truncates as a last resort', () {
      const cp = ActivityCounterparty(
        kind: 'user',
        id: '3328eed1-06c2-4a1a-9b7f-1234567890ab',
      );
      expect(cp.displayLabel, isNot(contains('-9b7f-1234567890ab')));
      expect(cp.displayLabel.length, lessThanOrEqualTo(6));
    });
  });

  group('ActivityCounterparty.initialLetter', () {
    test('derived from zendtag when present', () {
      const cp = ActivityCounterparty(kind: 'user', id: 'abc', zendtag: 'omooba');
      expect(cp.initialLetter, 'O');
    });

    test('derived from displayName when zendtag is missing', () {
      const cp = ActivityCounterparty(kind: 'user', id: 'abc', displayName: 'Blessed');
      expect(cp.initialLetter, 'B');
    });

    test('falls back to "?" when nothing is available and id is empty', () {
      const cp = ActivityCounterparty(kind: 'user', id: '');
      expect(cp.initialLetter, '?');
    });
  });
}
