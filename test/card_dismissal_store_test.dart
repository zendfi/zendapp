// Example-based test for Property 22 (implicit): Card_Dismissal_State
// persistence round-trips (Req 25.6).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zendapp/src/features/money/card_dismissal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CardDismissalStore', () {
    test('isDismissed defaults to false when never dismissed', () async {
      final store = CardDismissalStore();
      expect(await store.isDismissed(), isFalse);
    });

    test('dismiss() persists true, and isDismissed() reflects it after a simulated restart', () async {
      final store = CardDismissalStore();
      await store.dismiss();

      // Simulate an app restart: construct a fresh store instance.
      final restarted = CardDismissalStore();
      expect(await restarted.isDismissed(), isTrue);
    });

    test('dismiss() is idempotent — calling it twice keeps the state dismissed', () async {
      final store = CardDismissalStore();
      await store.dismiss();
      await store.dismiss();
      expect(await store.isDismissed(), isTrue);
    });
  });
}
