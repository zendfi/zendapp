import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/drop_models.dart';
import 'api_client.dart';

/// RSSI threshold above which a beacon is considered "close" (≥-55 dBm).
const int _kRssiThreshold = -55;

/// RSSI at which a beacon is considered too far and counter is reset.
const int _kRssiIgnore = -70;

/// Number of consecutive readings required above threshold.
const int _kConsecutiveRequired = 5;

/// Window in milliseconds within which all 5 readings must occur.
const int _kWindowMs = 500;

/// GATT connection timeout.
const Duration _kGattTimeout = Duration(seconds: 10);

/// Zend AppID bytes: "ZEND" = 0x5A 0x45 0x4E 0x44
const List<int> _kZendAppId = [0x5A, 0x45, 0x4E, 0x44];

/// UUID for the GATT service that carries the full beacon JSON payload.
/// Must match the value hardcoded in the Receiver platform code
/// (DropAdvertiserService on Android, DropBeaconIntent on iOS).
const String _kGattServiceUuid = '12345678-1234-1234-1234-123456789abc';
const String _kGattCharUuid = 'abcdefab-cdef-abcd-efab-cdefabcdefab';

/// Tracks per-device consecutive RSSI readings within a sliding 500 ms window.
///
/// [record] returns `true` exactly once when the 5-reading threshold is first
/// met for a device.  After that, [markGattInFlight] suppresses further
/// triggers until [reset] is called (e.g. on GATT failure or successful read).
class _RssiTracker {
  final String deviceId;
  final List<DateTime> _timestamps = [];
  int _count = 0;
  bool _gattInFlight = false;

  _RssiTracker(this.deviceId);

  /// Records an RSSI reading.
  ///
  /// Returns `true` if the consecutive-reading threshold was just met AND no
  /// GATT connection is already in flight for this device.
  bool record(int rssi) {
    if (rssi < _kRssiIgnore) {
      // Signal too weak — hard reset.
      reset();
      return false;
    }
    if (rssi < _kRssiThreshold) {
      // Mid-range: keep scanning but don't accumulate towards the threshold.
      return false;
    }

    final now = DateTime.now();
    _timestamps.add(now);

    // Drop readings older than the 500 ms window.
    _timestamps.removeWhere(
      (t) => now.difference(t).inMilliseconds > _kWindowMs,
    );
    _count = _timestamps.length;

    return _count >= _kConsecutiveRequired && !_gattInFlight;
  }

  void reset() {
    _count = 0;
    _timestamps.clear();
    _gattInFlight = false;
  }

  void markGattInFlight() => _gattInFlight = true;
}

/// Scans for nearby Zend BLE beacons and exposes a stream of discovered
/// [DiscoveredReceiver] lists, sorted by RSSI (strongest first).
///
/// Discovery flow:
/// 1. Scan continuously using `flutter_blue_plus`.
/// 2. Filter advertisements by the Zend AppID prefix.
/// 3. Gate on 5 consecutive RSSI readings ≥ -55 dBm within 500 ms.
/// 4. On threshold: fire `GET /drop/beacon/preview` and GATT connect in
///    parallel; validate Zendtag match; emit confirmed [DiscoveredReceiver].
///
/// Requirements: 2.1–2.9, 3.1–3.2, 9.3, 9.5, 11.5–11.8
class BleScannerService {
  final ApiClient _apiClient;

  BleScannerService({required ApiClient apiClient}) : _apiClient = apiClient;

  final _receiversController =
      StreamController<List<DiscoveredReceiver>>.broadcast();

  // deviceId → current in-memory state
  final Map<String, DiscoveredReceiver> _discovered = {};
  final Map<String, _RssiTracker> _trackers = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;

  /// Stream of discovered receivers sorted by RSSI (strongest signal first).
  ///
  /// The list is re-emitted whenever any receiver's state changes.
  Stream<List<DiscoveredReceiver>> get discoveredReceivers =>
      _receiversController.stream;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Starts a continuous BLE scan.
  ///
  /// Low-latency scan mode on Android ensures scan intervals ≤ 100 ms as
  /// required by Requirement 2.1.  Calling [startScan] while already scanning
  /// is a no-op.
  void startScan() {
    if (_scanning) return;
    _scanning = true;
    _discovered.clear();
    _trackers.clear();

    FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );

    _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
  }

  /// Stops the BLE scan and clears all tracked state.
  void stopScan() {
    if (!_scanning) return;
    _scanning = false;
    _scanSub?.cancel();
    _scanSub = null;
    FlutterBluePlus.stopScan();
    _discovered.clear();
    _trackers.clear();
  }

  /// Releases resources. Should be called when the owning widget is disposed.
  void dispose() {
    stopScan();
    _receiversController.close();
  }

  // ── Private scan handling ──────────────────────────────────────────────────

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      // Only process advertisements that contain a valid Zend AppID + nonce.
      final nonce = _extractNonce(result.advertisementData);
      if (nonce == null) continue;

      final deviceId = result.device.remoteId.str;
      final rssi = result.rssi;

      final tracker =
          _trackers.putIfAbsent(deviceId, () => _RssiTracker(deviceId));
      final thresholdMet = tracker.record(rssi);

      if (thresholdMet) {
        tracker.markGattInFlight();
        _onThresholdMet(result.device, deviceId, nonce, rssi);
      }
    }
  }

  /// Called once per device when the RSSI gate is satisfied.
  ///
  /// Immediately inserts a placeholder [DiscoveredReceiver] for UI feedback,
  /// then fires the preview API call and GATT connection in parallel
  /// (Requirement 2.3, 11.5).
  void _onThresholdMet(
    BluetoothDevice device,
    String deviceId,
    String nonce,
    int rssi,
  ) {
    // Placeholder entry gives the UI something to display immediately.
    _upsert(DiscoveredReceiver(
      deviceId: deviceId,
      nonce: nonce,
      rssi: rssi,
    ));

    // Run preview fetch and GATT in parallel; errors are handled independently.
    Future.wait([
      _fetchPreview(deviceId, nonce),
      _readGatt(device, deviceId, nonce),
    ]).catchError((_) {
      // Individual methods handle their own errors; this suppresses the
      // unhandled-rejection warning from Future.wait.
      return <void>[];
    });
  }

  // ── Preview API call ───────────────────────────────────────────────────────

  /// Fires `GET /drop/beacon/preview` and updates the discovered entry with the
  /// unconfirmed identity hint (Requirement 2.4, 11.6).
  ///
  /// A 404 from the server means the nonce is unknown or expired — no hint is
  /// shown, but GATT continues independently.
  Future<void> _fetchPreview(String deviceId, String nonce) async {
    try {
      final preview = await _apiClient.previewBeacon(nonce);
      final existing = _discovered[deviceId];
      if (existing == null) return; // Device was removed while awaiting.
      _upsert(existing.copyWith(preview: preview));
    } catch (_) {
      // 404 or network error — silently ignore; GATT is still in flight.
    }
  }

  // ── GATT connection ────────────────────────────────────────────────────────

  /// Opens a GATT connection, reads the beacon characteristic, validates the
  /// payload, and promotes the entry to confirmed (Requirements 3.1, 3.2,
  /// 11.7, 11.8).
  Future<void> _readGatt(
    BluetoothDevice device,
    String deviceId,
    String nonce,
  ) async {
    try {
      await device.connect(timeout: _kGattTimeout);
      final services = await device.discoverServices();

      BluetoothCharacteristic? targetChar;
      outer:
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            _kGattServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() ==
                _kGattCharUuid.toLowerCase()) {
              targetChar = char;
              break outer;
            }
          }
        }
      }

      if (targetChar == null) {
        _handleGattFailure(device, deviceId);
        return;
      }

      final List<int> value =
          await targetChar.read().timeout(_kGattTimeout);
      await device.disconnect();

      // Parse the JSON payload from the characteristic value.
      final json = String.fromCharCodes(value);
      late GattPayload payload;
      try {
        payload = GattPayload.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
      } catch (_) {
        _handleGattFailure(device, deviceId);
        return;
      }

      final existing = _discovered[deviceId];

      // Security check: if the preview already resolved, validate that the
      // Zendtag from the GATT payload matches (Requirement 11.8).
      if (existing?.preview != null &&
          existing!.preview!.zendtag != payload.zendtag) {
        // Zendtag mismatch — abort the flow, remove from discovered list.
        _discovered.remove(deviceId);
        _trackers[deviceId]?.reset();
        _emit();
        return;
      }

      // Promote to confirmed state.
      _upsert(DiscoveredReceiver(
        deviceId: deviceId,
        nonce: payload.nonce,
        rssi: existing?.rssi ?? 0,
        gattPayload: payload,
        preview: existing?.preview,
        isConfirmed: true,
      ));
    } catch (_) {
      _handleGattFailure(device, deviceId);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Handles any GATT failure: disconnects if possible, resets the tracker,
  /// removes the placeholder entry, and re-emits (Requirement 2.8).
  void _handleGattFailure(BluetoothDevice device, String deviceId) {
    try {
      device.disconnect();
    } catch (_) {}
    _discovered.remove(deviceId);
    _trackers[deviceId]?.reset();
    _emit();
  }

  void _upsert(DiscoveredReceiver receiver) {
    _discovered[receiver.deviceId] = receiver;
    _emit();
  }

  /// Emits the current discovered list sorted by RSSI descending
  /// (Requirement 2.9 — strongest signal first).
  void _emit() {
    final sorted = _discovered.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    _receiversController.add(sorted);
  }

  /// Extracts the nonce hex string from manufacturer-specific data if the
  /// Zend AppID prefix is present (Requirement 2.1).
  ///
  /// Advertisement packet layout (28 bytes):
  /// - Offset 0–3:   Zend AppID (0x5A454E44 = "ZEND")
  /// - Offset 4–11:  First 8 bytes of nonce (UUID bytes, big-endian)
  /// - Offset 12–15: Unix timestamp (big-endian uint32)
  /// - Offset 16–27: First 12 bytes of HMAC-SHA256 (sig hash)
  String? _extractNonce(AdvertisementData adv) {
    for (final entry in adv.manufacturerData.entries) {
      final bytes = entry.value;
      if (bytes.length < 28) continue;
      if (bytes[0] == _kZendAppId[0] &&
          bytes[1] == _kZendAppId[1] &&
          bytes[2] == _kZendAppId[2] &&
          bytes[3] == _kZendAppId[3]) {
        // Nonce is encoded as the first 8 bytes of the UUID at offset 4–11.
        final nonceBytes = bytes.sublist(4, 12);
        return nonceBytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }
    }
    return null;
  }
}
