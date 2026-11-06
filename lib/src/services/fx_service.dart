import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../core/zend_format.dart';
import '../models/api_models.dart';

class FxService {
  final ApiClient _apiClient;
  FxService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<FxPreviewResponse> getPreview(double amountUsd) async {
    return _apiClient.getFxPreview(amountUsd);
  }

  static const _rateKey = 'fx_ngn_per_usd_v1';
  static const _rateAtKey = 'fx_ngn_per_usd_at_v1';
  DateTime? _fetchedAt;

  /// Restores the last Naira rate seen, so the first frame already shows ₦
  /// instead of flipping from dollars once the network answers. A saved rate
  /// older than 3 days is dropped.
  Future<void> restoreNairaRate() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble(_rateKey);
    final at = prefs.getInt(_rateAtKey);
    if (rate == null || at == null) return;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age < const Duration(days: 3)) NairaRate.ngnPerUsd ??= rate;
  }

  /// Fetches the current rate at most every 10 minutes. Returns true when the
  /// rate shown changed. Failures keep the last rate.
  Future<bool> refreshNairaRate() async {
    final last = _fetchedAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return false;
    }
    _fetchedAt = DateTime.now();
    try {
      final r = await _apiClient.appkit('GET', '/fx/ngn');
      final rate = (r['ngn_per_usd'] as num?)?.toDouble();
      if (rate == null || !rate.isFinite || rate < 100 || rate > 100000) {
        return false;
      }
      final changed = NairaRate.ngnPerUsd != rate;
      NairaRate.ngnPerUsd = rate;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_rateKey, rate);
      await prefs.setInt(_rateAtKey, DateTime.now().millisecondsSinceEpoch);
      return changed;
    } catch (_) {
      return false;
    }
  }

  /// The current rate for pricing something in Naira right now, fetched fresh
  /// (not throttled). Null when Zend can't get one.
  Future<double?> currentNairaRate() async {
    _fetchedAt = null;
    await refreshNairaRate();
    return NairaRate.ngnPerUsd;
  }
}
