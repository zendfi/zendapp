/// Reads Ziro's on-chain state straight from a Sui GraphQL endpoint, not
/// through Zend core, so core can't hand the phone a key or an object it
/// made up (design.md §5.2, tasks 7.5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../services/sui_transaction_decoder.dart' show SuiBcsReader;
import '../../../services/sui_transaction_verifier.dart' show normaliseSuiAddress;
import 'ziro_bytes.dart';
import 'ziro_copy.dart';
import 'ziro_models.dart';

/// Build-time pins. When set they must agree with `/config`; when empty the
/// value from `/config` is used.
const String kZiroPinnedGraphqlUrl = String.fromEnvironment('ZIRO_SUI_GRAPHQL_URL');
const String kZiroPinnedPackageId = String.fromEnvironment('ZIRO_PACKAGE_ID');
const String kZiroPinnedRegistryId = String.fromEnvironment('ZIRO_REGISTRY_ID');
const String kZiroPinnedRelayer = String.fromEnvironment('ZIRO_RELAYER');
const String kZiroPinnedCoinType = String.fromEnvironment('ZIRO_COIN_TYPE');

/// The values every check trusts: build pins first, then `/config`.
class ZiroTrust {
  const ZiroTrust({
    required this.graphqlUrl,
    required this.packageId,
    required this.registryId,
    required this.relayer,
    required this.coinType,
    required this.testMode,
  });

  final String graphqlUrl;
  final String packageId;
  final String registryId;
  final String relayer;
  final String coinType;
  final bool testMode;

  factory ZiroTrust.from(ZiroConfig c) {
    String pick(String pinned, String fromServer, {bool address = false}) {
      if (pinned.isEmpty) {
        if (fromServer.isEmpty) throw const ZiroSafetyStop('missing config');
        return address ? normaliseSuiAddress(fromServer) : fromServer;
      }
      final p = address ? normaliseSuiAddress(pinned) : pinned;
      final s = fromServer.isEmpty
          ? p
          : (address ? normaliseSuiAddress(fromServer) : fromServer);
      if (p != s) throw const ZiroSafetyStop('config disagrees with build');
      return p;
    }

    final url = pick(kZiroPinnedGraphqlUrl, c.suiGraphqlUrl);
    final u = Uri.tryParse(url);
    final local = u != null && (u.host == 'localhost' || u.host == '127.0.0.1');
    if (u == null || !(u.scheme == 'https' || (c.testMode && local))) {
      throw const ZiroSafetyStop('graphql url');
    }
    return ZiroTrust(
      graphqlUrl: url,
      packageId: pick(kZiroPinnedPackageId, c.packageId, address: true),
      registryId: pick(kZiroPinnedRegistryId, c.registryId, address: true),
      relayer: pick(kZiroPinnedRelayer, c.relayer, address: true),
      coinType: ziroCanonicalType(pick(kZiroPinnedCoinType, c.coinType)),
      testMode: c.testMode,
    );
  }
}

/// `0x2::sui::SUI` → `0x000…002::sui::SUI`, recursively through generics,
/// the form the transaction decoder prints.
String ziroCanonicalType(String t) {
  return t.replaceAllMapped(
    RegExp(r'0x[0-9a-fA-F]{1,64}(?=::)'),
    (m) => normaliseSuiAddress(m.group(0)!),
  );
}

class ZiroObjectInfo {
  const ZiroObjectInfo({required this.type, required this.json});

  /// Full type, e.g. `0x…::ziro::Account`.
  final String type;
  final Map<String, dynamic> json;
}

class ZiroChainReader {
  ZiroChainReader(this.trust, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              contentType: 'application/json',
            ),
          );

  final ZiroTrust trust;
  final Dio _dio;
  String? _tableId;

  static final Map<String, (Uint8List, DateTime)> _verified = {};

  Future<Map<String, dynamic>?> _query(String q, Map<String, dynamic> vars) async {
    final r = await _dio.post<dynamic>(
      trust.graphqlUrl,
      data: jsonEncode({'query': q, 'variables': vars}),
    );
    final body = r.data is String ? jsonDecode(r.data as String) : r.data;
    if (body is! Map) return null;
    if (body['errors'] is List && (body['errors'] as List).isNotEmpty) {
      return null;
    }
    final d = body['data'];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// Type and JSON contents of a Move object, or null if there isn't one.
  Future<ZiroObjectInfo?> object(String id) async {
    final d = await _query(
      r'query($id: SuiAddress!) { object(address: $id) { asMoveObject { contents { type { repr } json } } } }',
      {'id': normaliseSuiAddress(id)},
    );
    final c = ((d?['object'] as Map?)?['asMoveObject'] as Map?)?['contents'] as Map?;
    if (c == null) return null;
    final type = (c['type'] as Map?)?['repr'] as String?;
    final json = c['json'];
    if (type == null) return null;
    return ZiroObjectInfo(
      type: ziroCanonicalType(type),
      json: json is Map ? Map<String, dynamic>.from(json) : const {},
    );
  }

  Future<String> _enclavesTable() async {
    final cached = _tableId;
    if (cached != null) return cached;
    final reg = await object(trust.registryId);
    // Types keep the package they were first published in, which differs
    // from `package_id` after an upgrade, so only the name is checked; the
    // object ID itself is the pinned or configured one.
    if (reg == null || !reg.type.endsWith('::ziro::Registry')) {
      throw const ZiroSafetyStop('registry');
    }
    final t = reg.json['enclaves'];
    final id = t is Map ? (t['id'] is Map ? (t['id'] as Map)['id'] : t['id']) : null;
    if (id is! String) throw const ZiroSafetyStop('registry table');
    return _tableId = normaliseSuiAddress(id);
  }

  /// The X25519 key the Registry holds for the enclave with [ed25519Pk], or
  /// null when that enclave isn't registered.
  Future<Uint8List?> registeredX25519(Uint8List ed25519Pk) async {
    final table = await _enclavesTable();
    final name = base64.encode(zCat([
      _uleb(ed25519Pk.length),
      ed25519Pk,
    ]));
    const sel =
        'dynamicField(name: {type: "vector<u8>", bcs: \$n}) { value { __typename ... on MoveValue { bcs json } } }';
    // Current schema first (`address`), then the older `owner` field.
    Map<String, dynamic>? field;
    for (final root in ['address', 'owner']) {
      final d = await _query(
        'query(\$t: SuiAddress!, \$n: Base64!) { $root(address: \$t) { $sel } }',
        {'t': table, 'n': name},
      );
      if (d == null) continue;
      final f = (d[root] as Map?)?['dynamicField'];
      field = f is Map ? Map<String, dynamic>.from(f) : null;
      break;
    }
    final value = field?['value'] as Map?;
    if (value == null) return null;
    // Enclave { pcr_hash: vector<u8>, x25519: vector<u8>, registered_ms: u64 }
    final bcs = value['bcs'];
    if (bcs is String) {
      try {
        final r = SuiBcsReader(zB64(bcs));
        r.readByteVector();
        final x = r.readByteVector();
        r.readU64();
        r.expectEnd();
        return x;
      } catch (_) {
        // Fall through to the JSON form.
      }
    }
    final j = value['json'];
    final x = j is Map ? j['x25519'] : null;
    if (x is String) return zB64(x);
    if (x is List) return Uint8List.fromList(x.cast<num>().map((n) => n.toInt()).toList());
    return null;
  }

  /// Throws [ZiroSafetyStop] unless [enclave]'s X25519 key is the one the
  /// on-chain Registry holds for its Ed25519 key. Cached for 10 minutes.
  Future<void> verifyEnclave(ZiroEnclaveRef enclave) async {
    final now = DateTime.now();
    final key = '${enclave.ed25519Pk}|${enclave.x25519Pk}';
    final hit = _verified[key];
    if (hit != null && now.difference(hit.$2) < const Duration(minutes: 10)) {
      return;
    }
    final Uint8List ed;
    final Uint8List x;
    try {
      ed = zB64(enclave.ed25519Pk);
      x = zB64(enclave.x25519Pk);
    } on FormatException {
      throw const ZiroSafetyStop('enclave keys');
    }
    if (ed.length != 32 || x.length != 32) {
      throw const ZiroSafetyStop('enclave key length');
    }
    final Uint8List? onChain;
    try {
      onChain = await registeredX25519(ed);
    } on ZiroSafetyStop {
      rethrow;
    } catch (e) {
      debugPrint('[Ziro] registry read failed: $e');
      throw const ZiroException(ZiroCopy.failed);
    }
    if (onChain == null || !zEqual(onChain, x)) {
      throw const ZiroSafetyStop('enclave not registered');
    }
    _verified[key] = (x, now);
  }

  static Uint8List _uleb(int n) {
    final out = <int>[];
    var v = n;
    do {
      var b = v & 0x7f;
      v >>= 7;
      if (v != 0) b |= 0x80;
      out.add(b);
    } while (v != 0);
    return Uint8List.fromList(out);
  }
}
