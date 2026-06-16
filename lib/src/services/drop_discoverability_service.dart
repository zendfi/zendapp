import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/drop/drop_debug_log.dart';
import '../models/drop_models.dart';
import 'api_client.dart';
import 'wallet_service.dart';

/// Manages the "Be Discoverable" state for Drop.
///
/// Discoverability is a user preference that persists across app launches.
/// When enabled, the device continuously broadcasts a signed BLE beacon so
/// nearby Zend users can find it and initiate a Drop transfer.
///
/// On Android: starts/stops the DropAdvertiserService foreground service.
/// On iOS: notifies the caller to show the "tap to broadcast" card since
/// iOS does not support indefinite background BLE advertising.
///
/// Key behaviours:
/// - State persists via SharedPreferences (key: 'drop_discoverable')
/// - Beacon auto-refreshes every ~25 seconds before expiry
/// - When the user sends a Drop, the service is paused and then resumed
///   automatically after the transfer completes
/// - On app startup, if discoverability was on, the service is restarted
class DropDiscoverabilityService extends ChangeNotifier {
  DropDiscoverabilityService({
    required ApiClient apiClient,
    required WalletService walletService,
  })  : _apiClient = apiClient,
        _walletService = walletService;

  final ApiClient _apiClient;
  // ignore: unused_field
  final WalletService _walletService;

  static const MethodChannel _channel =
      MethodChannel('com.zendfi.app/drop_advertiser');
  static const String _prefKey = 'drop_discoverable';

  bool _isDiscoverable = false;
  bool _isLoading = false;
  GattPayload? _currentPayload;
  Timer? _refreshTimer;

  /// Whether the device is currently advertising as discoverable.
  bool get isDiscoverable => _isDiscoverable;

  /// Whether a toggle operation is in progress (beacon fetch or service start).
  bool get isLoading => _isLoading;

  /// The active beacon payload, if currently advertising.
  GattPayload? get currentPayload => _currentPayload;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Loads the persisted preference and, if it was on, restarts advertising.
  /// Call this once after the user has authenticated.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final wasOn = prefs.getBool(_prefKey) ?? false;
    if (wasOn) {
      DropDebugLog.i.add('DISC', 'Restoring discoverability from saved preference');
      await _startAdvertising(fromInit: true);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Toggles discoverability on or off.
  Future<void> toggle() async {
    if (_isDiscoverable) {
      await _stop(userInitiated: true);
    } else {
      await _startAdvertising();
    }
  }

  /// Temporarily pauses advertising (e.g. while the sender is doing GATT).
  /// Does NOT change the persisted preference — resume() will bring it back.
  Future<void> pause() async {
    if (!_isDiscoverable) return;
    DropDebugLog.i.add('DISC', 'Pausing advertising (transfer in progress)');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _stopNativeService();
    // Don't change _isDiscoverable — we're still "logically" on
  }

  /// Resumes advertising after a pause. Re-fetches a fresh beacon.
  Future<void> resume() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldBeOn = prefs.getBool(_prefKey) ?? false;
    if (!shouldBeOn) return;
    DropDebugLog.i.add('DISC', 'Resuming advertising after transfer');
    await _startAdvertising(fromInit: true);
  }

  /// Stops advertising and turns off the preference permanently.
  Future<void> _stop({bool userInitiated = false}) async {
    DropDebugLog.i.add('DISC', 'Stopping discoverability (userInitiated=$userInitiated)');
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _currentPayload = null;
    _isDiscoverable = false;

    if (userInitiated) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, false);
    }

    await _stopNativeService();
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _startAdvertising({bool fromInit = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    DropDebugLog.i.add('DISC', 'Generating beacon for discoverability…');

    try {
      final beacon = await _apiClient.generateBeacon();
      final ttl = beacon.expiresAt -
          (DateTime.now().millisecondsSinceEpoch ~/ 1000);

      if (ttl < 10) {
        DropDebugLog.i.add('DISC',
            'Beacon TTL too short ($ttl s) after fetch — retrying',
            level: DropLogLevel.warn);
        _isLoading = false;
        notifyListeners();
        await _startAdvertising(fromInit: fromInit);
        return;
      }

      _currentPayload = GattPayload(
        zendtag: beacon.zendtag,
        nonce: beacon.nonce,
        timestamp: beacon.timestamp,
        expiresAt: beacon.expiresAt,
        signature: beacon.signature,
      );

      DropDebugLog.i.add('DISC',
          'Beacon OK: @${beacon.zendtag} TTL=${ttl}s nonce=${beacon.nonce.substring(0, 8)}…',
          level: DropLogLevel.ok);

      await _startNativeService(_currentPayload!);

      _isDiscoverable = true;
      _isLoading = false;

      // Persist preference
      if (!fromInit) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKey, true);
      }

      _scheduleRefresh(_currentPayload!);
      notifyListeners();
    } catch (e) {
      DropDebugLog.i.add('DISC', 'Failed to start discoverability: $e',
          level: DropLogLevel.error);
      _isLoading = false;
      _isDiscoverable = false;
      notifyListeners();
    }
  }

  void _scheduleRefresh(GattPayload payload) {
    _refreshTimer?.cancel();
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(payload.expiresAt * 1000);
    final refreshAt = expiresAt.subtract(const Duration(seconds: 5));
    final delay = refreshAt.difference(DateTime.now());

    if (delay.isNegative) {
      // Already stale — refresh immediately
      unawaited(_startAdvertising(fromInit: true));
      return;
    }

    DropDebugLog.i.add('DISC', 'Beacon refresh in ${delay.inSeconds}s');
    _refreshTimer = Timer(delay, () {
      DropDebugLog.i.add('DISC', 'Beacon expiry approaching — refreshing');
      unawaited(_startAdvertising(fromInit: true));
    });
  }

  Future<void> _startNativeService(GattPayload payload) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startAdvertising', {
          'zendtag': payload.zendtag,
          'nonce': payload.nonce,
          'timestamp': payload.timestamp,
          'expires_at': payload.expiresAt,
          'signature': payload.signature,
        });
        DropDebugLog.i.add('DISC', 'Android foreground service started',
            level: DropLogLevel.ok);
      } on PlatformException catch (e) {
        DropDebugLog.i.add('DISC',
            'Android service start failed: ${e.message}',
            level: DropLogLevel.error);
        rethrow;
      }
    }
    // iOS: advertising is handled natively via the widget App Intent.
    // The service just marks itself as logically on so the UI shows the
    // "tap to broadcast" card.
  }

  Future<void> _stopNativeService() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopAdvertising');
        DropDebugLog.i.add('DISC', 'Android foreground service stopped');
      } on PlatformException catch (_) {
        // Best-effort
      }
    }
  }

  // Allow unawaited usage
  // ignore: nothing_to_inline
  static void unawaited(Future<void> f) => f.catchError((_) {});
}
