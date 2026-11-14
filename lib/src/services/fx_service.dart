import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../core/zend_format.dart';
import '../models/api_models.dart';

/// Rates and the person's display currency ([DisplayCurrency]).
///
/// Both are saved on the device and restored before the first frame, so the
/// app opens in the right currency and a failed refresh keeps the last one
/// instead of falling back to dollars.
class FxService {
  final ApiClient _apiClient;
  FxService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<FxPreviewResponse> getPreview(double amountUsd) async {
    return _apiClient.getFxPreview(amountUsd);
  }

  static const _ratesKey = 'fx_rates_v2';
  static const _codeKey = 'display_currency_v1';
  // Before currencies: the Naira rate alone. Read once so an upgrade keeps ₦.
  static const _legacyNgnKey = 'fx_ngn_per_usd_v1';

  DateTime? _ratesAt;
  bool _currencyLoaded = false;

  /// Restores the saved currency and rates.
  Future<void> restoreNairaRate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ratesKey);
    if (raw != null) {
      try {
        final m = (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        );
        DisplayCurrency.rates = {...m, 'USD': 1};
      } catch (_) {}
    } else {
      final ngn = prefs.getDouble(_legacyNgnKey);
      if (ngn != null) DisplayCurrency.rates = {'USD': 1, 'NGN': ngn};
    }
    final code = prefs.getString(_codeKey);
    if (code != null) {
      DisplayCurrency.code = code;
    } else if (DisplayCurrency.rates.containsKey('NGN')) {
      // Upgrading from the Naira-only app: it showed Naira.
      DisplayCurrency.code = 'NGN';
    }
  }

  /// Refreshes the rates (at most every 10 minutes) and, once per session,
  /// the person's currency. Returns true when what's shown changed.
  /// Failures keep what was there.
  Future<bool> refreshNairaRate() async {
    var changed = false;
    final prefs = await SharedPreferences.getInstance();
    final last = _ratesAt;
    if (last == null ||
        DateTime.now().difference(last) >= const Duration(minutes: 10)) {
      _ratesAt = DateTime.now();
      try {
        final r = await _apiClient.appkit('GET', '/fx/rates');
        final m = (r['rates'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        )..removeWhere((_, v) => !v.isFinite || v <= 0);
        if (m.isNotEmpty) {
          final before = DisplayCurrency.rate;
          DisplayCurrency.rates = {...m, 'USD': 1};
          changed |= before != DisplayCurrency.rate;
          await prefs.setString(_ratesKey, jsonEncode(DisplayCurrency.rates));
        }
      } catch (_) {}
    }
    if (!_currencyLoaded) {
      try {
        final r = await _apiClient.appkit('GET', '/me/currency');
        final code = r['currency'] as String?;
        if (code != null && code.length == 3) {
          _currencyLoaded = true;
          changed |= code != DisplayCurrency.code;
          DisplayCurrency.code = code;
          await prefs.setString(_codeKey, code);
        }
      } catch (_) {}
    }
    return changed;
  }

  /// Changes the person's currency (Profile).
  Future<void> setCurrency(String code) async {
    final r = await _apiClient.appkit('PUT', '/me/currency', {'currency': code});
    final saved = r['currency'] as String? ?? code;
    DisplayCurrency.code = saved;
    _currencyLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, saved);
  }

  /// Sign-out: the next account loads its own currency.
  void forgetCurrency() => _currencyLoaded = false;

  /// The current Naira rate for pricing something in Naira right now,
  /// fetched fresh. Null when Zend can't get one.
  Future<double?> currentNairaRate() async {
    try {
      final r = await _apiClient.appkit('GET', '/fx/ngn');
      final rate = (r['ngn_per_usd'] as num?)?.toDouble();
      if (rate != null && rate.isFinite && rate >= 100 && rate <= 100000) {
        NairaRate.ngnPerUsd = rate;
      }
    } catch (_) {}
    return NairaRate.ngnPerUsd;
  }
}
