import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/appkit_service.dart';
import '../deeplink/deep_link_handler.dart';
import 'zapp_bridge.dart';
import 'zapp_host_mobile.dart'
    if (dart.library.js_interop) 'zapp_host_web.dart';

/// Plain-language description of each optional scope for the consent sheet.
const _scopeCopy = {
  'email': 'See your email',
  'wallet_address': 'Send money straight to you',
  'contacts': 'See people you choose to share',
};

/// Opens a ZApp from `/apps/{slug}` or an interaction from `/i/{id}`.
Future<void> openZAppLink(BuildContext context, DeepLinkPayload p) async {
  if (p.zappSlug != null) {
    await openZApp(context, p.zappSlug!);
    return;
  }
  final svc = AppKitService(ZendScope.of(context).walletService.apiClient);
  try {
    final i = await svc.getInteraction(p.interactionId!);
    if (!context.mounted) return;
    await openZApp(context, i['app'] as String, query: {'interaction': p.interactionId!});
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This isn't available to you.")),
      );
    }
  }
}

/// Opens a ZApp in a bottom sheet. Returns whatever the app passes to `close`.
/// [path] defaults to the app's entry; [query] adds launch params to it.
Future<Object?> openZApp(
  BuildContext context,
  String slug, {
  String? path,
  Map<String, String>? query,
}) {
  return showZendModalSheet<Object?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _ZAppSheet(slug: slug, path: path, query: query),
    ),
  );
}

class _ZAppSheet extends StatefulWidget {
  const _ZAppSheet({required this.slug, this.path, this.query});
  final String slug;
  final String? path;
  final Map<String, String>? query;

  String resolvedPath(ZAppDescriptor app) {
    final u = Uri.parse(path ?? app.entry);
    if (query == null || query!.isEmpty) return u.toString();
    return u.replace(queryParameters: {...u.queryParameters, ...query!}).toString();
  }
  @override
  State<_ZAppSheet> createState() => _ZAppSheetState();
}

class _ZAppSheetState extends State<_ZAppSheet> {
  ZAppDescriptor? _app;
  Map<String, dynamic>? _session;
  String? _error;
  bool _consenting = false;
  final Map<String, bool> _optional = {};
  bool _allowPosting = true;

  AppKitService get _svc =>
      AppKitService(ZendScope.of(context).walletService.apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final app = await _svc.descriptor(widget.slug);
      final s = await _svc.session(widget.slug);
      if (!mounted) return;
      setState(() {
        _app = app;
        if (s['needs_consent'] != true) _session = s;
        for (final p in app.permissions) {
          if (_scopeCopy.containsKey(p)) _optional[p] = false;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = "This app couldn't be opened.");
    }
  }

  Future<void> _connect() async {
    setState(() => _consenting = true);
    try {
      final s = await _svc.connect(
        widget.slug,
        scopes: _optional.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList(),
        allowPosting: _allowPosting && _app!.permissions.contains('post_card'),
      );
      if (mounted) setState(() => _session = s);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "That didn't go through. Try again.");
      }
    } finally {
      if (mounted) setState(() => _consenting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final app = _app;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (app == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        _Badge(app: app, onClose: () => Navigator.of(context).pop()),
        Divider(height: 1, color: zt.border),
        Expanded(
          child: _session == null
              ? _consent(context, app)
              : ZAppHost(
                  app: app,
                  path: widget.resolvedPath(app),
                  bridge: ZAppBridge(
                    context: context,
                    app: app,
                    session: _session!,
                    onClose: (r) => Navigator.of(context).pop(r),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _consent(BuildContext context, ZAppDescriptor app) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Continue to ${app.name} as ${model.currentDisplayName ?? 'you'}?',
          textAlign: TextAlign.center,
          style: s(20, w: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${app.name} will see your name, username and photo.',
          textAlign: TextAlign.center,
          style: s(14, c: zt.textSecondary),
        ),
        const SizedBox(height: 16),
        for (final e in _optional.entries)
          SwitchListTile(
            title: Text(_scopeCopy[e.key]!, style: s(15)),
            value: e.value,
            onChanged: (v) => setState(() => _optional[e.key] = v),
          ),
        if (app.permissions.contains('post_card'))
          SwitchListTile(
            title: Text('Post to your feed and chats', style: s(15)),
            subtitle: Text(
              'Only when you do something in the app',
              style: s(12, c: zt.textSecondary),
            ),
            value: _allowPosting,
            onChanged: (v) => setState(() => _allowPosting = v),
          ),
        const SizedBox(height: 8),
        Text(
          'You can change this anytime in Settings → Connected apps.',
          textAlign: TextAlign.center,
          style: s(12, c: zt.textSecondary),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          label: 'Continue',
          isLoading: _consenting,
          onPressed: _consenting ? null : _connect,
        ),
      ],
    );
  }
}

/// Zend-drawn header: app name, its real website, and the trust label.
/// The app can't draw over this, so users always know where they are.
class _Badge extends StatelessWidget {
  const _Badge({required this.app, required this.onClose});
  final ZAppDescriptor app;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final host = Uri.parse(app.origins.first).host;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: zt.bgSecondary,
            backgroundImage: app.iconUrl != null
                ? NetworkImage(app.iconUrl!)
                : null,
            child: app.iconUrl == null
                ? Icon(
                    PhosphorIconsRegular.squaresFour,
                    size: 14,
                    color: zt.textSecondary,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    color: zt.textPrimary,
                  ),
                ),
                Text(
                  app.trustLabel ?? host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 11,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIconsRegular.x, color: zt.textSecondary),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
