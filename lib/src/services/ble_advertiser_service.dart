import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../features/drop/drop_debug_log.dart';
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
    DropDebugLog.i.add('ADV', 'Starting advertising for @${payload.zendtag} nonce=${payload.nonce.substring(0, 8)}…');

    if (Platform.isAndroid) {
      await _startAndroid(payload);
    } else if (Platform.isIOS) {
      await _startIos(payload);
    }

    _scheduleRefresh(payload);
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    DropDebugLog.i.add('ADV', 'Stopping advertising');
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
      DropDebugLog.i.add('ADV', 'Android: MethodChannel startAdvertising OK', level: DropLogLevel.ok);
    } on PlatformException catch (e) {
      DropDebugLog.i.add('ADV', 'Android: MethodChannel failed: ${e.message}', level: DropLogLevel.error);
      throw Exception('Failed to start Android BLE advertising: ${e.message}');
    }
  }

  Future<void> _stopAndroid() async {
    try {
      await _kDropChannel.invokeMethod('stopAdvertising');
      DropDebugLog.i.add('ADV', 'Android: stopAdvertising OK');
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
      DropDebugLog.i.add('ADV', 'iOS: MethodChannel startAdvertising OK', level: DropLogLevel.ok);
    } on PlatformException catch (e) {
      DropDebugLog.i.add('ADV', 'iOS: MethodChannel failed: ${e.message}', level: DropLogLevel.error);
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
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(payload.expiresAt * 1000);
    final refreshAt = expiresAt.subtract(const Duration(seconds: 5));
    final delay = refreshAt.difference(DateTime.now());

    if (delay.isNegative) {
      DropDebugLog.i.add('ADV', 'Beacon already expired at scheduling, no refresh scheduled', level: DropLogLevel.warn);
      return;
    }

    DropDebugLog.i.add('ADV', 'Beacon refresh scheduled in ${delay.inSeconds}s');
    _refreshTimer = Timer(delay, () {
      DropDebugLog.i.add('ADV', 'Beacon about to expire — triggering refresh callback');
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
