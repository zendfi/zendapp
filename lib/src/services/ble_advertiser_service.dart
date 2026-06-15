import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/drop_models.dart';

/// Method channel for communication with the Android DropAdvertiserService.
/// Must match the channel name declared in DropAdvertiserService.kt.
const MethodChannel _kDropChannel = MethodChannel('com.zendfi.app/drop_advertiser');

/// Service and characteristic UUIDs used for GATT — must match BleScannerService constants.
const String kGattServiceUuid = '12345678-1234-1234-1234-123456789abc';
const String kGattCharUuid    = 'abcdefab-cdef-abcd-efab-cdefabcdefab';
const String kZendAppIdHex    = '5A454E44'; // "ZEND"

class BleAdvertiserService {
  GattPayload? _currentPayload;
  bool _isAdvertising = false;
  Timer? _refreshTimer;

  bool get isAdvertising => _isAdvertising;
  GattPayload? get currentPayload => _currentPayload;

  /// Start BLE advertising with the provided beacon payload.
  ///
  /// On Android: sends the payload to DropAdvertiserService via MethodChannel.
  /// On iOS: advertises via flutter_blue_plus peripheral mode (foreground only).
  Future<void> startAdvertising(GattPayload payload) async {
    _currentPayload = payload;
    _isAdvertising = true;

    if (Platform.isAndroid) {
      await _startAndroid(payload);
    } else if (Platform.isIOS) {
      await _startIos(payload);
    }

    _scheduleRefresh(payload);
  }

  Future<void> stopAdvertising() async {
    _isAdvertising = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _currentPayload = null;

    if (Platform.isAndroid) {
      await _stopAndroid();
    } else if (Platform.isIOS) {
      await _stopIos();
    }
  }

  // ── Android ──

  Future<void> _startAndroid(GattPayload payload) async {
    try {
      await _kDropChannel.invokeMethod('startAdvertising', {
        'zendtag': payload.zendtag,
        'nonce': payload.nonce,
        'timestamp': payload.timestamp,
        'expires_at': payload.expiresAt,
        'signature': payload.signature,
      });
    } on PlatformException catch (e) {
      // Log and rethrow so callers can handle permission errors etc.
      throw Exception('Failed to start Android BLE advertising: ${e.message}');
    }
  }

  Future<void> _stopAndroid() async {
    try {
      await _kDropChannel.invokeMethod('stopAdvertising');
    } on PlatformException catch (_) {
      // Best-effort stop
    }
  }

  // ── iOS ──
  // On iOS, BLE advertising requires CBPeripheralManager.
  // When the Drop sheet is open (foreground), flutter_blue_plus handles it
  // via a method channel call to the native layer.
  // The iOS widget/App Intent path is handled in the Swift extension (task 16).

  Future<void> _startIos(GattPayload payload) async {
    try {
      await _kDropChannel.invokeMethod('startAdvertising', {
        'zendtag': payload.zendtag,
        'nonce': payload.nonce,
        'timestamp': payload.timestamp,
        'expires_at': payload.expiresAt,
        'signature': payload.signature,
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to start iOS BLE advertising: ${e.message}');
    }
  }

  Future<void> _stopIos() async {
    try {
      await _kDropChannel.invokeMethod('stopAdvertising');
    } on PlatformException catch (_) {
      // Best-effort stop
    }
  }

  // ── Beacon refresh ──

  void _scheduleRefresh(GattPayload payload) {
    _refreshTimer?.cancel();

    // Refresh 5s before expiry
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      payload.expiresAt * 1000,
    );
    final refreshAt = expiresAt.subtract(const Duration(seconds: 5));
    final delay = refreshAt.difference(DateTime.now());

    if (delay.isNegative) {
      // Already expired or about to expire — caller should generate a fresh beacon
      return;
    }

    _refreshTimer = Timer(delay, () async {
      // Caller is responsible for generating a fresh beacon and calling
      // startAdvertising again. This timer just signals that refresh is needed.
      // In practice, the Drop sheet (or Android Foreground Service) handles this.
      // Here we expose a callback pattern if needed.
      _onRefreshNeeded?.call();
    });
  }

  /// Optional callback invoked when the current beacon is about to expire.
  /// The caller should generate a new beacon and call [startAdvertising] again.
  void Function()? _onRefreshNeeded;

  void setRefreshCallback(void Function() callback) {
    _onRefreshNeeded = callback;
  }

  void dispose() {
    stopAdvertising();
    _refreshTimer?.cancel();
  }
}
