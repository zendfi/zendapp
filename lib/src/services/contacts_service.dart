import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../models/recent_contact.dart';
import 'api_client.dart';

/// A device contact that resolved to a Zend account.
class ZendContact {
  const ZendContact({
    required this.zendtag,
    required this.displayName,
    this.avatarUrl,
    required this.deviceName,  // name as it appears in the phone contacts list
    required this.query,       // the email/phone that matched
  });

  final String zendtag;
  final String displayName;
  final String? avatarUrl;
  final String deviceName;
  final String query;
}

/// Reads the device contacts list and resolves them against Zend accounts.
///
/// On first call: requests READ_CONTACTS permission.
/// Results are cached in-memory for the app session and refreshed at most
/// once every 5 minutes.
class ContactsService extends ChangeNotifier {
  ContactsService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  List<ZendContact> _zendContacts = [];
  bool _loading = false;
  bool _permissionDenied = false;
  DateTime? _lastFetch;

  List<ZendContact> get zendContacts => List.unmodifiable(_zendContacts);
  bool get loading => _loading;
  bool get permissionDenied => _permissionDenied;
  bool get hasContacts => _zendContacts.isNotEmpty;

  /// Loads and resolves contacts.  Safe to call multiple times — debounced
  /// to once per 5 minutes.  Pass [force: true] to bypass the cache.
  Future<void> loadContacts({bool force = false}) async {
    if (_loading) return;
    if (!force && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return;
    }

    _loading = true;
    notifyListeners();

    try {
      // Request permission
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        _permissionDenied = true;
        _loading = false;
        notifyListeners();
        return;
      }

      // Read contacts with email + phone fields
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      // Collect all emails and phone numbers
      final queries = <String>[];
      final queryToName = <String, String>{}; // normalized query → device display name

      for (final contact in contacts) {
        final deviceName = contact.displayName;
        for (final email in contact.emails) {
          final normalized = email.address.toLowerCase().trim();
          if (normalized.isNotEmpty && normalized.contains('@')) {
            queries.add(normalized);
            queryToName[normalized] = deviceName;
          }
        }
        for (final phone in contact.phones) {
          // Normalize phone: strip spaces, dashes, parens; keep leading +
          final normalized = phone.number
              .replaceAll(RegExp(r'[\s\-\(\)]'), '')
              .toLowerCase()
              .trim();
          if (normalized.isNotEmpty) {
            queries.add(normalized);
            queryToName[normalized] = deviceName;
          }
        }
      }

      if (queries.isEmpty) {
        _zendContacts = [];
        _loading = false;
        _lastFetch = DateTime.now();
        notifyListeners();
        return;
      }

      // Batch resolve — server does a single DB query for all queries
      final resolved = await _apiClient.batchResolveContacts(queries);

      _zendContacts = resolved.map((r) {
        final query = r['query'] as String? ?? '';
        return ZendContact(
          zendtag: r['zendtag'] as String? ?? '',
          displayName: r['display_name'] as String? ?? '',
          avatarUrl: r['avatar_url'] as String?,
          deviceName: queryToName[query] ?? query,
          query: query,
        );
      }).toList();

      // De-duplicate by zendtag (same person may have multiple matching entries)
      final seen = <String>{};
      _zendContacts = _zendContacts.where((c) => seen.add(c.zendtag)).toList();

      _lastFetch = DateTime.now();
    } catch (e) {
      debugPrint('ContactsService: error loading contacts: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Converts Zend contacts to RecentContact for the payments sheet list.
  List<RecentContact> toRecentContacts() {
    return _zendContacts.map((c) {
      final label = c.deviceName.isNotEmpty ? c.deviceName[0].toUpperCase() : '?';
      return RecentContact(
        name: c.deviceName,
        tag: c.zendtag,
        avatarLabel: label,
        avatarUrl: c.avatarUrl,
      );
    }).toList();
  }
}
