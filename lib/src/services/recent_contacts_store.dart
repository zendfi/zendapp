import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/recent_contact.dart';

class RecentContactsStore {
  RecentContactsStore({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage;

  final FlutterSecureStorage _secureStorage;

  static const String _storageKey = 'zend_recent_contacts';

  Future<List<RecentContact>> load() async {
    final raw = await _secureStorage.read(key: _storageKey);
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RecentContact.fromJson)
          .where((contact) => contact.tag.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<RecentContact> contacts) async {
    final payload = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await _secureStorage.write(key: _storageKey, value: payload);
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _storageKey);
  }
}
