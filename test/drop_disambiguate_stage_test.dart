// Regression test for the Drop disambiguation-list reordering defect.
//
// BleScannerService re-emits its candidate list on every BLE scan result
// (several times a second) and RSSI genuinely fluctuates a few dBm per
// reading at close range. DropDisambiguateStage previously re-sorted on
// every rebuild with no stable item key, so two people at similar range
// could have their rows visually swap identity mid-gesture. This test
// asserts row order is frozen by device identity across rebuilds, even when
// the incoming RSSI order changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zendapp/src/features/drop/drop_disambiguate_stage.dart';
import 'package:zendapp/src/models/drop_models.dart';

DiscoveredReceiver _receiver(String deviceId, int rssi, String zendtag) {
  return DiscoveredReceiver(
    deviceId: deviceId,
    nonce: 'nonce-$deviceId',
    rssi: rssi,
    isConfirmed: true,
    preview: BeaconPreviewResponse(
      zendtag: zendtag,
      displayName: '',
      avatarUrl: null,
    ),
  );
}

/// Returns the zendtags in the order their rows currently appear on screen,
/// top to bottom. Each tile renders the zendtag twice (display-name fallback
/// + the "@handle" mono label below it), so this dedupes consecutive
/// repeats rather than asserting on raw widget count.
List<String> _visibleOrder(WidgetTester tester) {
  final raw = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.startsWith('@'))
      .toList();
  final deduped = <String>[];
  for (final s in raw) {
    if (deduped.isEmpty || deduped.last != s) deduped.add(s);
  }
  return deduped;
}

void main() {
  testWidgets(
    'candidate row order is frozen by device identity across RSSI-driven rebuilds',
    (tester) async {
      final a = _receiver('device-A', -50, 'alice');
      final b = _receiver('device-B', -55, 'bob');

      Widget buildStage(List<DiscoveredReceiver> candidates) {
        return MaterialApp(
          home: Scaffold(
            body: DropDisambiguateStage(
              amount: 10,
              candidates: candidates,
              onSelect: (_) {},
              onCancel: () {},
            ),
          ),
        );
      }

      // Initial render: alice is strongest (-50), shown first.
      await tester.pumpWidget(buildStage([a, b]));
      await tester.pumpAndSettle();
      expect(_visibleOrder(tester), ['@alice', '@bob']);

      // RSSI flips — bob is now reported stronger than alice, as BLE
      // scanning naturally re-sorts. The visible order must NOT flip: alice
      // stays first because that's the identity the user already saw.
      final bStronger = _receiver('device-B', -40, 'bob');
      final aWeaker = _receiver('device-A', -60, 'alice');
      await tester.pumpWidget(buildStage([bStronger, aWeaker]));
      await tester.pumpAndSettle();
      expect(_visibleOrder(tester), ['@alice', '@bob']);

      // A genuinely new device appears — it's appended, not inserted
      // wherever its RSSI would sort it, and existing rows keep their order.
      final c = _receiver('device-C', -30, 'carol');
      await tester.pumpWidget(buildStage([c, bStronger, aWeaker]));
      await tester.pumpAndSettle();
      expect(_visibleOrder(tester), ['@alice', '@bob', '@carol']);
    },
  );

  testWidgets('candidate tiles carry a stable key on deviceId', (tester) async {
    final a = _receiver('device-A', -50, 'alice');
    final b = _receiver('device-B', -55, 'bob');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DropDisambiguateStage(
          amount: 10,
          candidates: [a, b],
          onSelect: (_) {},
          onCancel: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Every row-level widget beneath the ListView should be keyed by a
    // ValueKey, not left to positional reconciliation.
    final keyedWidgets = tester
        .widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String>))
        .toList();
    final keyValues = keyedWidgets.map((w) => (w.key as ValueKey<String>).value).toSet();
    expect(keyValues, containsAll(['device-A', 'device-B']));
  });
}
