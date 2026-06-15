// Data models for the Zend Drop feature.
//
// Drop is a proximity-based USDC transfer that uses BLE beacons to discover
// nearby receivers. These models correspond to the backend `/api/zend/drop/`
// endpoints defined in `src/drop.rs`.

/// Response from `POST /api/zend/drop/beacon/generate`.
///
/// The Receiver stores this payload and serves it over GATT and BLE advertisement.
class BeaconGenerateResponse {
  final String zendtag;
  final String nonce;
  final int timestamp;

  /// Unix epoch seconds at which this beacon expires. JSON key: `expires_at`.
  final int expiresAt;
  final String signature;

  const BeaconGenerateResponse({
    required this.zendtag,
    required this.nonce,
    required this.timestamp,
    required this.expiresAt,
    required this.signature,
  });

  factory BeaconGenerateResponse.fromJson(Map<String, dynamic> json) {
    return BeaconGenerateResponse(
      zendtag: json['zendtag'] as String,
      nonce: json['nonce'] as String,
      timestamp: json['timestamp'] as int,
      expiresAt: json['expires_at'] as int,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zendtag': zendtag,
      'nonce': nonce,
      'timestamp': timestamp,
      'expires_at': expiresAt,
      'signature': signature,
    };
  }
}

/// The full beacon payload read from the Receiver's GATT characteristic.
///
/// Also used as the `beacon_payload` field in the `POST /api/zend/drop/execute`
/// request body — [toJson] serialises it back to the backend's expected shape.
class GattPayload {
  final String zendtag;
  final String nonce;
  final int timestamp;

  /// Unix epoch seconds at which this beacon expires. JSON key: `expires_at`.
  final int expiresAt;
  final String signature;

  const GattPayload({
    required this.zendtag,
    required this.nonce,
    required this.timestamp,
    required this.expiresAt,
    required this.signature,
  });

  factory GattPayload.fromJson(Map<String, dynamic> json) {
    return GattPayload(
      zendtag: json['zendtag'] as String,
      nonce: json['nonce'] as String,
      timestamp: json['timestamp'] as int,
      expiresAt: json['expires_at'] as int,
      signature: json['signature'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zendtag': zendtag,
      'nonce': nonce,
      'timestamp': timestamp,
      'expires_at': expiresAt,
      'signature': signature,
    };
  }
}

/// Response from `GET /api/zend/drop/beacon/preview?nonce=<nonce>`.
///
/// Returned before GATT completes so the Sender can show an unconfirmed
/// identity hint. The nonce status is never mutated by this call.
class BeaconPreviewResponse {
  final String zendtag;

  /// Human-readable display name. JSON key: `display_name`.
  final String displayName;

  /// CDN URL for the Receiver's avatar, if set. JSON key: `avatar_url`.
  final String? avatarUrl;

  const BeaconPreviewResponse({
    required this.zendtag,
    required this.displayName,
    this.avatarUrl,
  });

  factory BeaconPreviewResponse.fromJson(Map<String, dynamic> json) {
    return BeaconPreviewResponse(
      zendtag: json['zendtag'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}

/// Response from `POST /api/zend/drop/execute`.
///
/// Confirms that the Drop transfer was submitted to Solana and recorded in
/// `zend_transfers` with `source = 'drop'`.
class DropExecuteResponse {
  /// UUID of the created transfer record. JSON key: `transfer_id`.
  final String transferId;

  /// Solana transaction signature. JSON key: `tx_signature`.
  final String txSignature;
  final String status;

  const DropExecuteResponse({
    required this.transferId,
    required this.txSignature,
    required this.status,
  });

  factory DropExecuteResponse.fromJson(Map<String, dynamic> json) {
    return DropExecuteResponse(
      transferId: json['transfer_id'] as String,
      txSignature: json['tx_signature'] as String,
      status: json['status'] as String,
    );
  }
}

/// Internal model used by [BleScannerService] to track a verified nearby Receiver.
///
/// This is never serialised to/from JSON — it lives only in-memory on the
/// Sender device while the Drop sheet is open.
class DiscoveredReceiver {
  /// Platform BLE device identifier (e.g. MAC address on Android, UUID on iOS).
  final String deviceId;

  /// Nonce extracted from the BLE advertisement packet.
  final String nonce;

  /// Received Signal Strength Indicator in dBm (negative value).
  /// Higher (closer to zero) means stronger signal / shorter range.
  final int rssi;

  /// Full GATT payload — `null` until the GATT characteristic read completes.
  final GattPayload? gattPayload;

  /// Server-side preview — `null` until `GET /drop/beacon/preview` resolves.
  final BeaconPreviewResponse? preview;

  /// `true` once GATT has been read and the signature/nonce has been verified.
  final bool isConfirmed;

  const DiscoveredReceiver({
    required this.deviceId,
    required this.nonce,
    required this.rssi,
    this.gattPayload,
    this.preview,
    this.isConfirmed = false,
  });

  /// Returns a copy of this receiver with the given fields overridden.
  DiscoveredReceiver copyWith({
    String? deviceId,
    String? nonce,
    int? rssi,
    GattPayload? gattPayload,
    BeaconPreviewResponse? preview,
    bool? isConfirmed,
  }) {
    return DiscoveredReceiver(
      deviceId: deviceId ?? this.deviceId,
      nonce: nonce ?? this.nonce,
      rssi: rssi ?? this.rssi,
      gattPayload: gattPayload ?? this.gattPayload,
      preview: preview ?? this.preview,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}
