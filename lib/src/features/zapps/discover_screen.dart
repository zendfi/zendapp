import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import 'zapp_sheet.dart';

const _sections = [
  ('games', 'Games'),
  ('friends', 'With friends'),
  ('events', 'Events'),
  ('community', 'Community'),
  ('tools', 'Tools'),
];

/// Discover tab: apps Zend has checked and listed. Apps your connections use
/// come first. Opening one goes through the normal consent sheet.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<Map<String, dynamic>>? _apps;
  bool _failed = false;
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await ZendScope.of(context).walletService.apiClient.appkit('GET', '/apps/discover');
      if (!mounted) return;
      setState(() {
        _apps = (r['apps'] as List? ?? []).cast<Map<String, dynamic>>();
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontFamily: 'Geist', fontSize: size, fontWeight: w, color: c ?? zt.textPrimary);
    final all = _apps;
    final apps = all == null || _q.isEmpty
        ? all
        : all.where((a) => (a['name'] as String).toLowerCase().contains(_q)).toList();
    final friendsPicks = (apps ?? []).where((a) => (a['friends_using'] as num? ?? 0) > 0).take(6).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('Discover', style: s(26, w: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Text('Games and tools you can use with your people.', style: s(14, c: zt.textSecondary)),
              ),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search apps',
                  prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, color: zt.textSecondary, size: 20),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(PhosphorIconsRegular.x, size: 18, color: zt.textSecondary),
                          onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                          }),
                        ),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZendRadii.pill), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 4),
              if (_failed)
                _Empty(text: "Couldn't load apps. Pull to try again.", zt: zt)
              else if (apps == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (apps.isEmpty)
                _Empty(text: _q.isEmpty ? 'New apps are on the way. Check back soon.' : 'No apps called "${_search.text.trim()}"', zt: zt)
              else if (_q.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final a in apps) _AppTile(app: a),
              ]
              else ...[
                if (friendsPicks.isNotEmpty) ...[
                  _Header('Your people use these', zt),
                  for (final a in friendsPicks) _AppTile(app: a),
                ],
                for (final (key, title) in _sections)
                  if (apps.any((a) => a['category'] == key && !friendsPicks.contains(a))) ...[
                    _Header(title, zt),
                    for (final a in apps.where((a) => a['category'] == key && !friendsPicks.contains(a)))
                      _AppTile(app: a),
                  ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.zt);
  final String text;
  final ZendTheme zt;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(text, style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary)),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.zt});
  final String text;
  final ZendTheme zt;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary))),
  );
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app});
  final Map<String, dynamic> app;

  String _social() {
    final f = (app['friends_using'] as num? ?? 0).toInt();
    final p = (app['people_using'] as num? ?? 0).toInt();
    if (f == 1) return '1 of your people uses this';
    if (f > 1) return '$f of your people use this';
    if (p > 0) return '$p people use this';
    return 'New';
  }

  String? _how() => switch (app['results']) {
    'checked' => 'Checked afterwards so nobody can cheat',
    'app' => 'Results decided by ${app['name']}',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final icon = app['icon_url'] as String?;
    final how = _how();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openZApp(context, app['slug'] as String),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: zt.bgPrimary,
                    child: icon != null
                        ? Image.network(icon, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(PhosphorIconsRegular.squaresFour, color: zt.textSecondary))
                        : Icon(PhosphorIconsRegular.squaresFour, color: zt.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(app['name'] as String,
                              style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600, color: zt.textPrimary)),
                        ),
                        Text(app['connected'] == true ? 'Open' : 'Get',
                            style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.accent)),
                      ]),
                      if (app['description'] is String) ...[
                        const SizedBox(height: 2),
                        Text(app['description'] as String,
                            style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary)),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        [if (app['developer'] is String) 'By ${app['developer']}', _social(), ?how].join(' · '),
                        style: TextStyle(fontFamily: 'Geist', fontSize: 11, color: zt.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
