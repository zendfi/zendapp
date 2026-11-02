import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/api_client.dart';

/// Developer tools are shown on Zend for web at desktop width only.
bool developerToolsAvailable(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= 900;

/// Settings → Developer: create ZApps, upload manifests, add testers.
/// Same endpoints as `zend apps ...`, using the signed-in session.
class DeveloperAppsScreen extends StatefulWidget {
  const DeveloperAppsScreen({super.key});
  @override
  State<DeveloperAppsScreen> createState() => _DeveloperAppsScreenState();
}

class _DeveloperAppsScreenState extends State<DeveloperAppsScreen> {
  List<Map<String, dynamic>>? _apps;
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _newKeys; // shown once after create
  final _slug = TextEditingController();
  final _name = TextEditingController();
  final _manifest = TextEditingController();
  final _tester = TextEditingController();
  String? _message;
  List<String> _errors = const [];
  bool _busy = false;

  Future<Map<String, dynamic>> _call(String m, String p, [Object? body]) =>
      ZendScope.of(context).walletService.apiClient.appkit(m, p, body as Map<String, dynamic>?);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_slug, _name, _manifest, _tester]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _call('GET', '/apps');
      if (!mounted) return;
      setState(() {
        _apps = (r['apps'] as List).cast<Map<String, dynamic>>();
        if (_selected != null) {
          _selected = _apps!.where((a) => a['id'] == _selected!['id']).firstOrNull;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _apps = const []);
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _message = null;
      _errors = const [];
    });
    try {
      await f();
    } on ApiException catch (e) {
      _message = e.userMessage;
    } catch (e) {
      _message = 'Something went wrong. Try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
    final r = await _call('POST', '/apps', {'slug': _slug.text.trim(), 'name': _name.text.trim()});
    _newKeys = r;
    _slug.clear();
    _name.clear();
    await _load();
    _selected = _apps?.where((a) => a['id'] == r['id']).firstOrNull;
  });

  Future<void> _deploy() => _run(() async {
    final Map<String, dynamic> manifest;
    try {
      manifest = Map<String, dynamic>.from(jsonDecode(_manifest.text) as Map);
    } catch (_) {
      _message = 'Manifest is not valid JSON.';
      return;
    }
    try {
      final r = await _call('PUT', '/apps/${_selected!['id']}/manifest', manifest);
      _message = 'Deployed version ${r['manifest_version']} (${r['status']}).';
    } on AppKitValidationException catch (e) {
      _message = e.message;
      _errors = e.errors;
    }
    await _load();
  });

  Future<void> _addTester() => _run(() async {
    await _call('POST', '/apps/${_selected!['id']}/testers', {'zendtag': _tester.text.trim()});
    _message = 'Added @${_tester.text.trim().replaceFirst('@', '')}.';
    _tester.clear();
  });

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c, String? f}) =>
        TextStyle(fontFamily: f ?? 'Geist', fontSize: size, fontWeight: w, color: c ?? zt.textPrimary);
    if (!developerToolsAvailable(context)) {
      return Scaffold(
        body: Center(child: Text('Open Zend on a computer to manage your apps.', style: s(14, c: zt.textSecondary))),
      );
    }
    final apps = _apps;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                    ),
                    const SizedBox(width: 10),
                    Text('Your apps', style: s(22, w: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 16),
                  if (apps == null) const Center(child: CircularProgressIndicator()),
                  for (final a in apps ?? const <Map<String, dynamic>>[])
                    ListTile(
                      selected: _selected?['id'] == a['id'],
                      title: Text(a['name'] as String, style: s(14, w: FontWeight.w600)),
                      subtitle: Text('${a['slug']} · ${a['status']} · v${a['manifest_version'] ?? '-'}',
                          style: s(12, c: zt.textSecondary)),
                      onTap: () => setState(() {
                        _selected = a;
                        _newKeys = null;
                        _message = null;
                        _errors = const [];
                      }),
                    ),
                  const Divider(height: 32),
                  Text('New app', style: s(14, w: FontWeight.w600)),
                  TextField(controller: _slug, decoration: const InputDecoration(labelText: 'Slug (e.g. coinflip)')),
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 12),
                  PrimaryButton(label: 'Create', isLoading: _busy, onPressed: _busy ? null : _create),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: zt.border),
            Expanded(
              child: _selected == null
                  ? Center(child: Text('Pick an app or create one.', style: s(14, c: zt.textSecondary)))
                  : ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(_selected!['name'] as String, style: s(24, w: FontWeight.w700)),
                        SelectableText('https://app.usezend.app/apps/${_selected!['slug']}',
                            style: s(13, c: zt.textSecondary)),
                        if (_newKeys != null) _KeysCard(keys: _newKeys!),
                        const SizedBox(height: 20),
                        Text('Manifest', style: s(15, w: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _manifest,
                          maxLines: 16,
                          style: s(12, f: 'monospace'),
                          decoration: const InputDecoration(
                            hintText: 'Paste zapp.json',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 180,
                            child: PrimaryButton(label: 'Deploy', isLoading: _busy, onPressed: _busy ? null : _deploy),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text('Testers', style: s(15, w: FontWeight.w600)),
                        Row(children: [
                          Expanded(child: TextField(controller: _tester, decoration: const InputDecoration(hintText: '@username'))),
                          TextButton(onPressed: _busy ? null : _addTester, child: const Text('Add')),
                        ]),
                        if (_message != null) ...[
                          const SizedBox(height: 16),
                          Text(_message!, style: s(13)),
                        ],
                        for (final e in _errors) Text('• $e', style: s(12, c: ZendColors.destructive)),
                        const SizedBox(height: 24),
                        Text('Deploy from CI with `zend apps deploy zapp.json` and ZEND_APP_KEY. Docs: github.com/zendfi/zend-appkit',
                            style: s(12, c: zt.textSecondary)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeysCard extends StatelessWidget {
  const _KeysCard({required this.keys});
  final Map<String, dynamic> keys;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    Widget row(String label, String v) => Row(children: [
      SizedBox(width: 150, child: Text(label, style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary))),
      Expanded(child: SelectableText(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
      IconButton(
        icon: const Icon(PhosphorIconsRegular.copy, size: 16),
        onPressed: () => Clipboard.setData(ClipboardData(text: v)),
      ),
    ]);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: zt.border), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Copy these now. They won\'t be shown again.',
            style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w600, color: zt.textPrimary)),
        const SizedBox(height: 8),
        row('ZEND_APP_KEY', keys['api_key'] as String),
        row('ZEND_WEBHOOK_SECRET', keys['webhook_secret'] as String),
      ]),
    );
  }
}
