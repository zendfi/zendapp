/// Pay-to-read (AppKit primitives R11, design D11): opens what the person
/// bought, on this device.
///
/// Decryption runs in `zend_seal.js` (built from `seal/`), loaded into Zend's
/// own page on web and a hidden webview on mobile. ZApp pages never reach it.
/// The bundle has no network or keys of its own: this class signs for it
/// (`SuiZkLoginService.signPersonalMessage`, a 30-minute read-only session
/// key) and carries its key requests to Zend's relay, which can't read them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';
import 'seal_engine_io.dart'
    if (dart.library.js_interop) 'seal_engine_web.dart';
import 'sui_zklogin_service.dart';

/// What [UnlockReader] needs from the bundle: JSON in, JSON out.
abstract class SealEngine {
  Future<String> call(String method, String argsJson);
}

/// Callbacks the bundle makes into Dart, all JSON strings.
class SealHost {
  const SealHost({required this.sign, required this.fetchKey});

  /// Base64 personal message in, base64 zkLogin signature out.
  final Future<String> Function(String messageB64) sign;

  /// `{"body","headers"}` in, `{"status","headers","body"}` out.
  final Future<String> Function(String argsJson) fetchKey;
}

class UnlockException implements Exception {
  const UnlockException(this.code, this.message);

  /// `bad_data`, `wrong_item`, `no_access`, `expired` or `unavailable`.
  final String code;
  final String message;

  @override
  String toString() => message;
}

class UnlockReader {
  UnlockReader({required ApiClient api, required SuiZkLoginService zkLogin})
    : _api = api,
      _zk = zkLogin;

  final ApiClient _api;
  final SuiZkLoginService _zk;
  SealEngine? _engine;
  Map<String, dynamic>? _keyServers;
  DateTime? _keyServersAt;

  Future<SealEngine> _engineReady() async => _engine ??= await createSealEngine(
    SealHost(
      sign: (m) => _zk.signPersonalMessage(base64.decode(m)),
      fetchKey: (argsJson) async {
        final a = jsonDecode(argsJson) as Map<String, dynamic>;
        final r = await _api.appkit('POST', '/seal/fetch_key', {
          'request': jsonDecode(a['body'] as String),
          'headers': a['headers'],
        });
        return jsonEncode(r);
      },
    ),
  );

  Future<Map<String, dynamic>> _servers() async {
    final at = _keyServersAt;
    if (_keyServers != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return _keyServers!;
    }
    final r = await _api.appkit('GET', '/seal/key-servers');
    _keyServersAt = DateTime.now();
    return _keyServers = r;
  }

  Future<dynamic> _call(String method, Map<String, dynamic> args) async {
    final engine = await _engineReady();
    final out =
        jsonDecode(await engine.call(method, jsonEncode(args)))
            as Map<String, dynamic>;
    if (out['ok'] == true) return out['value'];
    final e = (out['error'] as Map?) ?? const {};
    final code = '${e['code'] ?? 'unavailable'}';
    throw UnlockException(code, switch (code) {
      'no_access' => "You haven't unlocked this yet",
      'wrong_item' || 'bad_data' => "That content can't be opened",
      _ => "That didn't open. Try again.",
    });
  }

  /// The identity [data] was encrypted under (hex, no `0x`), without
  /// decrypting it.
  Future<String> identity(Uint8List data) async {
    final v = await _call('inspect', {'data': base64.encode(data)});
    return (v as Map)['id'] as String;
  }

  /// Opens [data] (an encrypted object) from [listingId]. [txKindB64] is the
  /// `seal_approve` transaction kind with the person's receipt, from the
  /// backend.
  Future<Uint8List> open({
    required String listingId,
    required String txKindB64,
    required Uint8List data,
  }) async {
    final ks = await _servers();
    final plain = await _call('decrypt', {
      'packageId': ks['package_id'],
      'listingId': listingId,
      'address': ks['address'],
      'keyServers': {
        'objectId': ks['object_id'],
        'objectBcs': ks['object_bcs'],
        'fieldBcs': ks['field_bcs'],
        'version': ks['version'],
      },
      'txKind': txKindB64,
      'data': base64.encode(data),
    });
    return base64.decode(plain as String);
  }

  /// Sign-out: drops the session key and fetched keys.
  Future<void> forget() async {
    _keyServers = null;
    if (_engine != null) await _call('forget', const {});
  }
}
