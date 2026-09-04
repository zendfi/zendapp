import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'sui_salt_drive_store.dart';
import 'sui_salt_shares.dart';

/// Owns the 2-of-3 custody of the zkLogin salt across device, Drive, and backend.
///
/// The salt is the second factor of zkLogin's `(live JWT, salt)` pair. Splitting
/// it does not change theft resistance — the OAuth binding already provides that
/// — it removes the single point of *loss*. Any two holders reconstruct it, so no
/// outage, deletion, or company shutdown permanently locks a user out.
///
/// Reconstruction happens here, in memory, and the result is handed straight to
/// the caller. Nothing reconstructed is ever written back to disk.
class SuiSaltCustodyService {
  SuiSaltCustodyService({
    required ApiClient apiClient,
    required FlutterSecureStorage secureStorage,
    SuiSaltDriveStore driveStore = const SuiSaltDriveStore(),
  }) : _api = apiClient,
       _storage = secureStorage,
       _drive = driveStore;

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final SuiSaltDriveStore _drive;

  /// Share A. Device-local, and deliberately absent on web.
  static const _shareAKey = 'zend_zklogin_salt_share_a';

  /// Whether this platform keeps a device share at all.
  ///
  /// False on web: browser storage is readable by any XSS and is destroyed when
  /// the user clears site data, so a share there is both weaker and a liability.
  /// Web reconstructs from Drive + backend every session and stores nothing, which
  /// leaves the 2-of-3 threshold intact — it consumes shares rather than holding
  /// one.
  bool get keepsDeviceShare => !kIsWeb;

  Future<String?> readDeviceShare() async {
    if (!keepsDeviceShare) return null;
    return _storage.read(key: _shareAKey);
  }

  Future<void> _writeDeviceShare(String share) async {
    if (!keepsDeviceShare) return;
    await _storage.write(key: _shareAKey, value: share);
  }

  /// Forgets the device share. Used by the device-loss drill and on sign-out.
  Future<void> clearDeviceShare() => _storage.delete(key: _shareAKey);

  /// Splits [salt] into three shares and distributes them.
  ///
  /// Ordering is the safety property here:
  ///   1. write share B to Drive,
  ///   2. **read it back** to prove it is durable,
  ///   3. provision share C to the backend, which flips the strategy,
  ///   4. only then keep share A locally.
  ///
  /// If any step fails the account stays on its previous strategy, which is
  /// recoverable. Flipping the strategy before B is confirmed would leave the user
  /// holding A + C, where losing the device loses the funds — precisely the
  /// failure this scheme exists to prevent.
  ///
  /// [accessToken] and [idToken] must come from the same OAuth grant, and
  /// [idToken] must be recent: the backend requires a fresh authentication before
  /// accepting share material.
  Future<void> provisionShares({
    required Uint8List salt,
    required String sessionId,
    required String idToken,
    required String accessToken,
    bool rotating = false,
  }) async {
    final shares = SaltSharing.split(salt);
    try {
      final encoded = shares.map((share) => share.encode()).toList();

      await _drive.writeShare(accessToken, encoded[1]);

      // Verify rather than assume. A silently failed write here is the difference
      // between a recoverable account and an unrecoverable one.
      final confirmed = await _drive.readShare(accessToken);
      if (confirmed != encoded[1]) {
        throw const SuiSaltDriveException(
          'Your recovery share could not be confirmed in Google Drive',
        );
      }

      await _api.provisionSuiSaltShares(
        sessionId: sessionId,
        idToken: idToken,
        shareC: encoded[2],
        rotating: rotating,
      );

      await _writeDeviceShare(encoded[0]);
    } finally {
      for (final share in shares) {
        share.zeroize();
      }
    }
  }

  /// Reconstructs the salt from whichever two shares are reachable.
  ///
  /// Prefers device + Drive, because that combination needs no backend round trip
  /// and works even if we are down. Falls back to Drive + backend (the new-device
  /// path), then device + backend (for a user who revoked Drive access).
  ///
  /// The caller owns the returned bytes and must zeroize them after use.
  /// [freshAuth] mints a *freshly re-authenticated* session and ID token, and is
  /// invoked only if the device and Drive shares were not enough.
  ///
  /// The backend refuses to release share C unless the token proves the provider
  /// authenticated the person within the last few minutes, and it fails closed
  /// when the `auth_time` claim is absent entirely. Google only emits `auth_time`
  /// when the request carried `max_age` or `prompt=login`, so the ambient
  /// sign-in token — obtained with `prompt=select_account` — never satisfies it
  /// and the release returns 401. Hence a purpose-made grant rather than reusing
  /// the session's token.
  ///
  /// Lazily invoked on purpose: a device that still holds share A combines it with
  /// Drive and never prompts, so the interruption only happens when the backend
  /// share is genuinely required.
  Future<Uint8List> reconstructSalt({
    required String sessionId,
    required String idToken,
    String? accessToken,
    Future<({String sessionId, String idToken})> Function()? freshAuth,
  }) async {
    final collected = <SaltShare>[];
    final failures = <String>[];

    final deviceShare = await readDeviceShare();
    if (deviceShare != null && deviceShare.isNotEmpty) {
      try {
        collected.add(SaltShare.decode(deviceShare));
      } catch (error) {
        // A corrupt local share must not block recovery via the other two.
        failures.add('device share unreadable ($error)');
      }
    }

    if (accessToken != null && accessToken.isNotEmpty) {
      try {
        final driveShare = await _drive.readShare(accessToken);
        if (driveShare != null && driveShare.isNotEmpty) {
          collected.add(SaltShare.decode(driveShare));
        } else {
          failures.add('no share stored in Google Drive');
        }
      } catch (error) {
        failures.add('Google Drive unavailable ($error)');
      }
    } else {
      failures.add('no Google Drive access was granted this session');
    }

    // Only ask the backend when the two cheaper shares were not enough. This
    // keeps routine signing independent of us, and keeps share releases rare
    // enough that a burst of them is a meaningful signal.
    if (collected.length < 2) {
      try {
        var releaseSessionId = sessionId;
        var releaseIdToken = idToken;
        if (freshAuth != null) {
          final grant = await freshAuth();
          releaseSessionId = grant.sessionId;
          releaseIdToken = grant.idToken;
        }
        final shareC = await _api.releaseSuiSaltShare(
          sessionId: releaseSessionId,
          idToken: releaseIdToken,
        );
        collected.add(SaltShare.decode(shareC));
      } catch (error) {
        failures.add('backend share unavailable ($error)');
      }
    }

    if (collected.length < 2) {
      throw SuiSaltRecoveryException(
        'Could not gather enough recovery shares. ${failures.join('; ')}',
      );
    }

    try {
      return SaltSharing.combine(collected);
    } finally {
      for (final share in collected) {
        share.zeroize();
      }
    }
  }

  /// Re-splits the same salt into fresh shares.
  ///
  /// The address is unchanged, because the salt is unchanged. What changes is that
  /// previously leaked shares stop combining with the new ones — which is the
  /// point of rotation, and why it is mandatory after a suspected compromise.
  /// [freshAuth] is forwarded to [reconstructSalt] and used only if the device and
  /// Drive shares were not enough. Without it, gathering share C would fall back to
  /// [idToken] — an ordinary sign-in token with no `auth_time` claim — which the
  /// backend refuses with 401.
  Future<void> rotateShares({
    required String sessionId,
    required String idToken,
    required String accessToken,
    Future<({String sessionId, String idToken})> Function()? freshAuth,
  }) async {
    final salt = await reconstructSalt(
      sessionId: sessionId,
      idToken: idToken,
      accessToken: accessToken,
      freshAuth: freshAuth,
    );
    try {
      await provisionShares(
        salt: salt,
        sessionId: sessionId,
        idToken: idToken,
        accessToken: accessToken,
        rotating: true,
      );
    } finally {
      for (var i = 0; i < salt.length; i++) {
        salt[i] = 0;
      }
    }
  }
}

/// Fewer than two shares could be gathered, so the salt cannot be rebuilt.
class SuiSaltRecoveryException implements Exception {
  const SuiSaltRecoveryException(this.message);
  final String message;

  @override
  String toString() => 'SuiSaltRecoveryException: $message';
}
