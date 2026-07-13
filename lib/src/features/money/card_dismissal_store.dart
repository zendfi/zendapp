import 'package:shared_preferences/shared_preferences.dart';

/// Persists Card_Dismissal_State — whether this User has dismissed the
/// Debit_Card_Teaser (Req 25.6). `SharedPreferences`-backed, following the
/// exact existing pattern used for `notifications_muted` in
/// `activity_screen.dart`/`legacy_activity_list_view.dart` and the Phase 2/3
/// `activity_view_mode` key — not a backend column/table (design.md decision
/// 3: no cross-device sync requirement, so no new migration/endpoint needed).
class CardDismissalStore {
  static const _key = 'debit_card_teaser_dismissed';

  Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
