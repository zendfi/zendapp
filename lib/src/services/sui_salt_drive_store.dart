import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Stores share B of the sharded zkLogin salt in the user's Google Drive
/// `appdata` folder.
///
/// ## Why Drive, on every platform
///
/// The wallet address derives from a Google `sub`, so recovery must be anchored to
/// the *same* Google account. The existing Solana recovery packet uses iCloud on
/// iOS, which would be wrong here: a user who set up on iPhone and moved to
/// Android could not reach their share, leaving only the backend's — which
/// reconstructs nothing. So this uses Drive on both platforms.
///
/// ## Why the access token is passed in
///
/// The token comes from the same OAuth grant as the zkLogin ID token. Obtaining
/// it separately (through `google_sign_in`, say) would let the Drive account and
/// the zkLogin account diverge and write the share into the wrong person's Drive.
/// Taking it as a parameter keeps that impossible rather than merely unlikely.
///
/// `appdata` is a hidden per-app folder: the app cannot see any of the user's
/// other files, and Google classifies the scope as non-sensitive.
class SuiSaltDriveStore {
  const SuiSaltDriveStore();

  static const _fileName = 'zend_zklogin_share.json';
  static const _mimeType = 'application/json';
  static const _spaces = 'appDataFolder';

  /// Writes share B, replacing any existing copy.
  ///
  /// Throws [SuiSaltDriveException] on failure. Callers must not treat a failed
  /// write as recoverable: an account left holding only the device and backend
  /// shares loses everything with the device.
  Future<void> writeShare(String accessToken, String shareB) async {
    final client = _AuthorizedClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final existing = await _find(api);
      final bytes = utf8.encode(jsonEncode({'version': 1, 'share': shareB}));
      final media = drive.Media(
        Stream.fromIterable([bytes]),
        bytes.length,
        contentType: _mimeType,
      );

      if (existing != null) {
        await api.files.update(drive.File(), existing.id!, uploadMedia: media);
      } else {
        final metadata = drive.File()
          ..name = _fileName
          ..parents = [_spaces];
        await api.files.create(metadata, uploadMedia: media);
      }
    } catch (error) {
      throw SuiSaltDriveException('Could not save your recovery share: $error');
    } finally {
      client.close();
    }
  }

  /// Reads share B, or null when the user has none stored.
  ///
  /// A null result is a legitimate state — the user may never have provisioned,
  /// or may have revoked the app's Drive access — and is distinct from an error.
  Future<String?> readShare(String accessToken) async {
    final client = _AuthorizedClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final file = await _find(api);
      if (file == null) return null;

      final media = await api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = await media.stream.fold<List<int>>(
        <int>[],
        (accumulated, chunk) => accumulated..addAll(chunk),
      );

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const SuiSaltDriveException('Recovery share is malformed');
      }
      final share = decoded['share'];
      if (share is! String || share.isEmpty) {
        throw const SuiSaltDriveException('Recovery share is malformed');
      }
      return share;
    } on SuiSaltDriveException {
      rethrow;
    } catch (error) {
      throw SuiSaltDriveException('Could not read your recovery share: $error');
    } finally {
      client.close();
    }
  }

  /// Removes share B. Used when rotating away from a compromised share set.
  Future<void> deleteShare(String accessToken) async {
    final client = _AuthorizedClient(accessToken);
    try {
      final api = drive.DriveApi(client);
      final existing = await _find(api);
      if (existing == null) return;
      await api.files.delete(existing.id!);
    } catch (error) {
      throw SuiSaltDriveException('Could not remove your recovery share: $error');
    } finally {
      client.close();
    }
  }

  Future<drive.File?> _find(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: _spaces,
      q: "name = '$_fileName'",
      $fields: 'files(id,name)',
    );
    final files = result.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }
}

/// Attaches the caller-supplied bearer token to every Drive request.
class _AuthorizedClient extends http.BaseClient {
  _AuthorizedClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Drive was unreachable, refused the request, or returned something unusable.
class SuiSaltDriveException implements Exception {
  const SuiSaltDriveException(this.message);
  final String message;

  @override
  String toString() => 'SuiSaltDriveException: $message';
}
