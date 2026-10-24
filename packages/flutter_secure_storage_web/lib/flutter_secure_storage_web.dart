/// Web implementation of flutter_secure_storage for Zend.
///
/// Replaces upstream flutter_secure_storage_web 1.2.1, which
///  * imported dart:html / dart:js_util, blocking `flutter build web --wasm`;
///  * wrote values to **localStorage** (shared by every tab, kept forever),
///    and stored the AES key it "encrypted" them with right next to them, so
///    the encryption added nothing.
///
/// This version keeps everything in **sessionStorage**: values live only in
/// the tab that wrote them and disappear when it closes. A session token
/// can't outlive the tab, can't be read from another tab, and isn't left on
/// disk after the browser shuts down.
///
/// What it does not do, and nothing in browser storage can: protect against
/// script already running in our origin (XSS). That is the CSP's job
/// (vercel.json), together with the app's idle sign-out on web.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

class FlutterSecureStorageWeb extends FlutterSecureStoragePlatform {
  static void registerWith(Registrar registrar) {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  }

  /// Every key is namespaced so deleteAll never touches storage that isn't
  /// ours (e.g. flutter_web_auth_2's handoff key).
  static const _prefix = 'zend.ss.';

  web.Storage get _store => web.window.sessionStorage;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _store.getItem('$_prefix$key') != null;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      _store.removeItem('$_prefix$key');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    for (final k in _ourKeys()) {
      _store.removeItem(k);
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _store.getItem('$_prefix$key');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return {
      for (final k in _ourKeys())
        k.substring(_prefix.length): _store.getItem(k) ?? '',
    };
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      _store.setItem('$_prefix$key', value);

  List<String> _ourKeys() {
    final keys = <String>[];
    for (var i = 0; i < _store.length; i++) {
      final k = _store.key(i);
      if (k != null && k.startsWith(_prefix)) keys.add(k);
    }
    return keys;
  }
}
