import 'api_client.dart';

/// What the client needs to open a ZApp (from `/apps/by-slug/:slug`).
class ZAppDescriptor {
  ZAppDescriptor(this.raw);
  final Map<String, dynamic> raw;

  String get slug => raw['slug'] as String;
  String get name => raw['name'] as String;
  String? get iconUrl => raw['icon_url'] as String?;
  bool get reviewed => raw['reviewed'] == true;

  /// "Made by Tunde. Not checked by Zend." for unreviewed apps; null when reviewed.
  String? get trustLabel => raw['trust_label'] as String?;

  /// Who made it, from the manifest's `developer.name` (public apps).
  String? get developerName => (raw['developer'] as Map?)?['name'] as String?;

  /// `app` | `checked` | `none`: how results are decided.
  String get results => raw['results'] as String? ?? 'none';

  /// Plain-language line about results, or null when there are none.
  String? get resultsLine => switch (results) {
    'checked' => 'Checked afterwards so nobody can cheat',
    'app' => 'Results decided by $name',
    _ => null,
  };
  String get custody => raw['custody'] as String? ?? 'contract';
  List<String> get origins => (raw['origins'] as List? ?? []).cast<String>();
  List<String> get permissions =>
      (raw['permissions'] as List? ?? []).cast<String>();
  String get entry => raw['entry'] as String? ?? '/';
  List<Map<String, dynamic>> get chatActions =>
      (raw['chat_actions'] as List? ?? []).cast<Map<String, dynamic>>();

  Uri entryUri([String? path]) =>
      Uri.parse(origins.first).resolve(path ?? entry);

  /// True only for URLs on one of the app's registered origins.
  bool allows(Uri uri) => origins.any((o) {
    final u = Uri.parse(o);
    return uri.scheme == u.scheme && uri.host == u.host && uri.port == u.port;
  });
}

class AppKitService {
  AppKitService(this._api);
  final ApiClient _api;

  Future<ZAppDescriptor> descriptor(String slug) async =>
      ZAppDescriptor(await _api.appkit('GET', '/apps/by-slug/$slug'));

  /// Returns a session, or `{needs_consent: true}` on first use.
  Future<Map<String, dynamic>> session(String slug) =>
      _api.appkit('GET', '/apps/by-slug/$slug/session');

  Future<Map<String, dynamic>> connect(
    String slug, {
    required List<String> scopes,
    required bool allowPosting,
  }) => _api.appkit('POST', '/apps/by-slug/$slug/connect', {
    'scopes': scopes,
    'allow_posting': allowPosting,
  });

  Future<void> disconnect(String slug) =>
      _api.appkit('DELETE', '/apps/by-slug/$slug/grant');

  Future<List<Map<String, dynamic>>> connectedApps() async =>
      ((await _api.appkit('GET', '/me/connected-apps'))['apps'] as List? ?? [])
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createInteraction(
    String slug,
    Map<String, dynamic> params,
  ) => _api.appkit('POST', '/apps/interactions', {...params, 'app': slug});

  Future<Map<String, dynamic>> getInteraction(String id) =>
      _api.appkit('GET', '/apps/interactions/$id');

  Future<Map<String, dynamic>> updateInteraction(
    String id,
    Map<String, dynamic> params,
  ) => _api.appkit('PATCH', '/apps/interactions/$id', params);

  Future<Map<String, dynamic>> postCard(Map<String, dynamic> params) =>
      _api.appkit('POST', '/apps/cards', params);

  Future<List<Map<String, dynamic>>> feed() async =>
      ((await _api.appkit('GET', '/apps/feed'))['cards'] as List? ?? [])
          .cast<Map<String, dynamic>>();

  /// Returns a one-time ticket, or throws if the app's limits don't allow it.
  Future<String> payCheck(
    String slug, {
    required double amountUsd,
    required String to,
    String? reference,
  }) async =>
      (await _api.appkit('POST', '/apps/by-slug/$slug/pay-check', {
            'amount_usd': amountUsd,
            'to': to,
            'reference': ?reference,
          }))['ticket']
          as String;

  Future<void> payReport(
    String slug, {
    required String ticket,
    required String transferId,
  }) => _api.appkit('POST', '/apps/by-slug/$slug/pay-report', {
    'ticket': ticket,
    'transfer_id': transferId,
  });
}
