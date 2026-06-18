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
  bool _appInForeground = true;
  GattPayload? _currentPayload;
  Timer? _refreshTimer;
  String? _lastError;

  // ── Constructor / init ─────────────────────────────────────────────────────

  void _setupNativeCallbackListener() {
    const callbackChannel = MethodChannel('com.zendfi.app/drop_advertiser');
    callbackChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPermissionDenied') {
        DropDebugLog.i.add('DISC', 'BLE permission denied by user', level: DropLogLevel.error);
        _isLoading = false;
        _isDiscoverable = false;
        _lastError = 'Bluetooth permission required. '
            'Go to Settings → Apps → Zend! App → Permissions → Nearby devices → Allow.';
        notifyListeners();
      }
    });
  }

  /// Whether the device is currently advertising as discoverable.
  bool get isDiscoverable => _isDiscoverable;

  /// Whether a toggle operation is in progress (beacon fetch or service start).
  bool get isLoading => _isLoading;

  /// The active beacon payload, if currently advertising.
  GattPayload? get currentPayload => _currentPayload;

  /// Set when the last start attempt failed. Null if no error.
  /// On Android 15 OEM devices, this may be a battery optimization message.
  String? get lastError => _lastError;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Loads the persisted preference and, if it was on, restarts advertising.
  /// Call this once after the user has authenticated.
  Future<void> init() async {
    _setupNativeCallbackListener();
    final prefs = await SharedPreferences.getInstance();
    final wasOn = prefs.getBool(_prefKey) ?? false;
    if (wasOn) {
      DropDebugLog.i.add('DISC', 'Restoring discoverability from saved preference');
      await _startAdvertising(fromInit: true);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call when the app goes to background — pauses the refresh timer so
  /// we don't fire MethodChannel calls while the activity is paused (which
  /// would queue up dozens of deferred starts on Android 15).
  void onAppBackground() {
    _appInForeground = false;
    // Cancel the refresh timer — the service keeps running; we'll reschedule
    // on foreground resume so the beacon is fresh when the app is visible again.
    _refreshTimer?.cancel();
    _refreshTimer = null;
    DropDebugLog.i.add('DISC', 'App backgrounded — refresh timer paused');
  }

  /// Call when the app returns to foreground — resumes the refresh cycle.
  Future<void> onAppForeground() async {
    _appInForeground = true;
    DropDebugLog.i.add('DISC', 'App foregrounded — checking beacon state');
    if (!_isDiscoverable) return;

    // If the current beacon is stale (expired or about to expire), refresh now.
    final payload = _currentPayload;
    if (payload == null) {
      await _startAdvertising(fromInit: true);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ttlRemaining = payload.expiresAt - now;
    if (ttlRemaining < 10) {
      DropDebugLog.i.add('DISC', 'Beacon stale on foreground ($ttlRemaining s) — refreshing immediately');
      await _startAdvertising(fromInit: true);
    } else {
      // Beacon still valid — just reschedule the refresh timer
      _scheduleRefresh(payload);
    }
  }

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
    // Small delay so the sender's BLE scanner teardown completes before we
    // restart advertising — prevents the receiver immediately re-triggering
    // a scan hit on the same device that just finished a transfer.
    await Future.delayed(const Duration(milliseconds: 800));
    // Reset loading flag in case a previous _startAdvertising failed mid-flight
    // and left _isLoading=true — without this reset the resume() is a no-op.
    _isLoading = false;
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
      _lastError = null;

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
      // Surface a user-visible error for the FGS_BLOCKED case so the profile
      // tile can show a hint about battery optimization settings.
      if (e is PlatformException && e.code == 'FGS_BLOCKED') {
        if (e.message == 'SERVICE_NOT_RUNNING') {
          // Could be permission denial OR battery restriction — check permissions
          final hasPerms = await _checkBlePermsQuiet();
          if (!hasPerms) {
            _lastError = 'Nearby devices permission required.\n'
                'Go to Settings → Apps → Zend! App → Permissions → Nearby devices → Allow.';
          } else {
            _lastError = 'Android restricted the background service.\n'
                'Go to Settings → Battery → Zend! App → set to "Unrestricted".';
          }
        } else {
          _lastError = e.message;
        }
      } else {
        _lastError = null;
      }
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
      // Only restart the native service if it's currently running.
      // If the app is backgrounded and the service is alive, we still need
      // to refresh the beacon so new senders get a valid nonce — but we
      // must only call _startNativeService when the activity is foreground
      // (Android 15 restriction). _startAdvertising handles this correctly
      // via the MethodChannel defer mechanism in MainActivity.
      unawaited(_startAdvertising(fromInit: true));
    });
  }

  Future<void> _startNativeService(GattPayload payload) async {
    if (!Platform.isAndroid) return;

    if (!_appInForeground) {
      DropDebugLog.i.add('DISC', 'App backgrounded — skipping native start (will restart on foreground)');
      return;
    }

    try {
      // Check permissions first. If not granted, startAdvertising will trigger
      // the system dialog natively — but we MUST NOT do the isServiceRunning
      // check in that case, since the service hasn't had a chance to start yet.
      final hasPerms = await _channel.invokeMethod<bool>('checkBlePermissions') ?? false;

      await _channel.invokeMethod('startAdvertising', {
        'zendtag': payload.zendtag,
        'nonce': payload.nonce,
        'timestamp': payload.timestamp,
        'expires_at': payload.expiresAt,
        'signature': payload.signature,
      });

      if (!hasPerms) {
        // Permission dialog is now showing — return without the isServiceRunning
        // check. The service will start once the user grants permission, and the
        // next beacon refresh cycle will confirm it's running.
        DropDebugLog.i.add('DISC', 'Permission dialog shown — skipping service confirmation check');
        return;
      }

      DropDebugLog.i.add('DISC', 'startService() called — waiting for service to confirm');
      await Future.delayed(const Duration(milliseconds: 500));
      final running = await _isServiceRunning();
      if (!running) {
        DropDebugLog.i.add('DISC',
            'Service not running after start — BLE permission denied or battery restriction',
            level: DropLogLevel.error);
        throw PlatformException(code: 'FGS_BLOCKED', message: 'SERVICE_NOT_RUNNING');
      }
      DropDebugLog.i.add('DISC', 'Android foreground service confirmed running', level: DropLogLevel.ok);
    } on PlatformException catch (e) {
      DropDebugLog.i.add('DISC', 'Service start failed: ${e.message}', level: DropLogLevel.error);
      rethrow;
    }
  }

  Future<bool> _isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _checkBlePermsQuiet() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkBlePermissions');
      return result ?? true;
    } catch (_) {
      return true;
    }
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
