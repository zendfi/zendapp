import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/appkit_service.dart';
import '../deeplink/deep_link_handler.dart';
import 'zapp_bridge.dart';
import 'zapp_live.dart';
import 'zapp_host_mobile.dart'
    if (dart.library.js_interop) 'zapp_host_web.dart';
import 'zapp_web_url_stub.dart'
    if (dart.library.js_interop) 'zapp_web_url_web.dart';

/// Plain-language description of each optional scope for the consent screen.
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
    await openZApp(
      context,
      i['app'] as String,
      query: {'interaction': p.interactionId!},
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This isn't available to you.")),
      );
    }
  }
}

/// Opens a ZApp full screen, like a screen of Zend itself. On mobile there is no
/// URL, header or browser chrome; on web the address bar shows
/// `app.usezend.app/apps/<slug>`. Returns whatever the app passes to `close`.
/// [path] defaults to the app's entry; [query] adds launch params to it.
Future<Object?> openZApp(
  BuildContext context,
  String slug, {
  String? path,
  Map<String, String>? query,
}) {
  return Navigator.of(context, rootNavigator: true).push<Object?>(
    PageRouteBuilder<Object?>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) =>
          _ZAppScreen(slug: slug, path: path, query: query),
      transitionsBuilder: (_, a, _, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class _ZAppScreen extends StatefulWidget {
  const _ZAppScreen({required this.slug, this.path, this.query});
  final String slug;
  final String? path;
  final Map<String, String>? query;

  String resolvedPath(ZAppDescriptor app) {
    final u = Uri.parse(path ?? app.entry);
    if (query == null || query!.isEmpty) return u.toString();
    return u
        .replace(queryParameters: {...u.queryParameters, ...query!})
        .toString();
  }

  @override
  State<_ZAppScreen> createState() => _ZAppScreenState();
}

class _ZAppScreenState extends State<_ZAppScreen> {
  ZAppDescriptor? _app;
  Map<String, dynamic>? _session;
  String? _error;
  bool _consenting = false;
  bool _ready = false;
  Color? _background;
  final Map<String, bool> _optional = {};
  bool _allowPosting = true;
  bool _shareWithFriends = false;
  final _handle = ZAppHostHandle();
  late final VoidCallback _leaveUrl;
  bool _closing = false;

  AppKitService get _svc =>
      AppKitService(ZendScope.of(context).walletService.apiClient);

  @override
  void initState() {
    super.initState();
    // Browser back arrives as a normal back press (see PopScope below).
    _leaveUrl = enterZAppUrl(widget.slug);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Live rooms the page joined; closed with the app.
  ZAppLiveRooms? _live;

  /// People picked through `people.pick`, for this app session only.
  final Map<String, String> _picks = {};

  ZAppLiveRooms _rooms() => _live ??= ZAppLiveRooms(
    api: ZendScope.read(context).walletService.apiClient,
    push: (event) => _handle.push(jsonEncode(event)),
  );

  @override
  void dispose() {
    _live?.dispose();
    _leaveUrl();
    super.dispose();
  }

  void _close([Object? result]) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(result);
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
        shareWithFriends: _shareWithFriends,
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

  Future<void> _onLeave(Uri uri) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave Zend?'),
        content: Text(
          '${_app?.name ?? 'This app'} wants to open something outside Zend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (ok == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _menu() async {
    final app = _app;
    if (app == null) return;
    await showZendModalSheet<void>(
      context: context,
      builder: (c) => _AppMenu(
        app: app,
        onReport: () async {
          Navigator.pop(c);
          await _report(app);
        },
        onDisconnect: () async {
          Navigator.pop(c);
          await _svc.disconnect(app.slug);
          _close();
        },
        onClose: () {
          Navigator.pop(c);
          _close();
        },
      ),
    );
  }

  Future<void> _report(ZAppDescriptor app) async {
    const reasons = {
      'scam': 'It looks like a scam',
      'unfair_result': 'A result was unfair',
      'offensive': "It's offensive",
      'broken': "It doesn't work",
      'other': 'Something else',
    };
    final reason = await showZendModalSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                "What's wrong?",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final e in reasons.entries)
              ListTile(
                title: Text(e.value),
                onTap: () => Navigator.pop(c, e.key),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ZendScope.of(context).walletService.apiClient.appkit(
        'POST',
        '/apps/by-slug/${app.slug}/report',
        {'reason': reason},
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks. Zend will take a look.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("That didn't go through. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final app = _app;
    final bg = _background ?? zt.bgPrimary;
    final dark = bg.computeLuminance() < 0.45;
    final overlay =
        (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent);

    Widget body;
    if (_error != null) {
      body = _Message(text: _error!, onClose: _close);
    } else if (app == null) {
      body = const _Splash(app: null);
    } else if (_session == null) {
      body = _consent(context, app);
    } else {
      final host = ZAppHost(
        app: app,
        path: widget.resolvedPath(app),
        handle: _handle,
        onLeave: _onLeave,
        onReady: (c) => setState(() {
          _ready = true;
          _background = c;
        }),
        bridge: ZAppBridge(
          context: context,
          app: app,
          session: _session!,
          onClose: _close,
          live: _rooms(),
          picks: _picks,
        ),
      );
      body = kIsWeb
          ? Column(
              children: [
                _WebBar(app: app, onMenu: _menu, onClose: _close),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: host),
                      if (!_ready) Positioned.fill(child: _Splash(app: app)),
                    ],
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(child: SafeArea(bottom: false, child: host)),
                if (!_ready) Positioned.fill(child: _Splash(app: app)),
                _ExitPill(app: app, onClose: () => _close(), onMenu: _menu),
              ],
            );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Android back: step back inside the app first, then leave it.
        if (_session != null && await _handle.back()) return;
        _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(backgroundColor: bg, body: body),
      ),
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
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(PhosphorIconsRegular.x, color: zt.textSecondary),
              onPressed: _close,
            ),
          ),
          const SizedBox(height: 24),
          Center(child: _AppIcon(app: app, size: 72)),
          const SizedBox(height: 16),
          Text(
            app.name,
            textAlign: TextAlign.center,
            style: s(24, w: FontWeight.w700),
          ),
          if (app.developerName != null)
            Text(
              'By ${app.developerName}',
              textAlign: TextAlign.center,
              style: s(13, c: zt.textSecondary),
            ),
          if (app.trustLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              app.trustLabel!,
              textAlign: TextAlign.center,
              style: s(12, c: zt.textSecondary),
            ),
          ],
          if (app.resultsLine != null) ...[
            const SizedBox(height: 6),
            Text(
              app.resultsLine!,
              textAlign: TextAlign.center,
              style: s(12, c: zt.textSecondary),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Continue as ${model.currentDisplayName ?? 'you'}?',
            textAlign: TextAlign.center,
            style: s(17, w: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${app.name} will see your name, username and photo.',
            textAlign: TextAlign.center,
            style: s(14, c: zt.textSecondary),
          ),
          const SizedBox(height: 12),
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
              onChanged: (v) => setState(() {
                _allowPosting = v;
                if (!v) _shareWithFriends = false;
              }),
            ),
          if (app.permissions.contains('post_card') && _allowPosting)
            SwitchListTile(
              title: Text('Share results with your friends', style: s(15)),
              subtitle: Text(
                'Friends you chat with can see what it posts to your feed',
                style: s(12, c: zt.textSecondary),
              ),
              value: _shareWithFriends,
              onChanged: (v) => setState(() => _shareWithFriends = v),
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
          TextButton(
            onPressed: _close,
            child: Text('Not now', style: s(14, c: zt.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});
  final ZAppDescriptor? app;
  final double size;
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final url = app?.iconUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.26),
      child: Container(
        width: size,
        height: size,
        color: zt.bgSecondary,
        child: url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  PhosphorIconsRegular.squaresFour,
                  size: size * 0.45,
                  color: zt.textSecondary,
                ),
              )
            : Icon(
                PhosphorIconsRegular.squaresFour,
                size: size * 0.45,
                color: zt.textSecondary,
              ),
      ),
    );
  }
}

/// Native launch screen while the app loads: its icon and name, nothing else.
class _Splash extends StatelessWidget {
  const _Splash({required this.app});
  final ZAppDescriptor? app;
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return ColoredBox(
      color: zt.bgPrimary,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AppIcon(app: app, size: 84),
            if (app != null) ...[
              const SizedBox(height: 16),
              Text(
                app!.name,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: zt.textPrimary,
                ),
              ),
              if (app!.trustLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  app!.trustLabel!,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: zt.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Geist', color: zt.textPrimary),
              ),
              const SizedBox(height: 16),
              TextButton(onPressed: onClose, child: const Text('Back to Zend')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The only Zend chrome on mobile: a small floating pill. It opens expanded so
/// people learn it's there, folds into a dot after a few seconds, and can be
/// dragged up and down so it never covers the app's own buttons.
class _ExitPill extends StatefulWidget {
  const _ExitPill({
    required this.app,
    required this.onClose,
    required this.onMenu,
  });
  final ZAppDescriptor app;
  final VoidCallback onClose;
  final VoidCallback onMenu;
  @override
  State<_ExitPill> createState() => _ExitPillState();
}

class _ExitPillState extends State<_ExitPill> {
  bool _expanded = true;
  double _top = 8;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleCollapse();
  }

  void _scheduleCollapse() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final height = MediaQuery.of(context).size.height;
    const fg = Colors.white;
    final pill = Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: _expanded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 6),
                  _AppIcon(app: widget.app, size: 24),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      widget.app.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'More',
                    icon: const Icon(
                      PhosphorIconsBold.dotsThree,
                      color: fg,
                      size: 18,
                    ),
                    onPressed: widget.onMenu,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                    icon: const Icon(PhosphorIconsBold.x, color: fg, size: 16),
                    onPressed: widget.onClose,
                  ),
                  const SizedBox(width: 2),
                ],
              )
            : InkWell(
                onTap: () {
                  setState(() => _expanded = true);
                  _scheduleCollapse();
                },
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(PhosphorIconsBold.caretLeft, color: fg, size: 14),
                ),
              ),
      ),
    );
    return Positioned(
      top: pad.top + _top,
      right: 8,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() {
          _top = (_top + d.delta.dy).clamp(
            0.0,
            height - pad.top - pad.bottom - 60,
          );
        }),
        child: pill,
      ),
    );
  }
}

/// Web: a slim Zend bar above the app, so it reads as a page inside Zend.
class _WebBar extends StatelessWidget {
  const _WebBar({
    required this.app,
    required this.onMenu,
    required this.onClose,
  });
  final ZAppDescriptor app;
  final VoidCallback onMenu;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        border: Border(bottom: BorderSide(color: zt.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to Zend',
            icon: Icon(PhosphorIconsRegular.arrowLeft, color: zt.textPrimary),
            onPressed: onClose,
          ),
          Image.asset(
            'assets/icons/zend-icon-navbar.png',
            width: 16,
            height: 16,
            color: zt.textSecondary,
          ),
          const SizedBox(width: 10),
          _AppIcon(app: app, size: 22),
          const SizedBox(width: 8),
          Text(
            app.name,
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: zt.textPrimary,
            ),
          ),
          if (app.trustLabel != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                app.trustLabel!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  color: zt.textSecondary,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'More',
            icon: Icon(PhosphorIconsRegular.dotsThree, color: zt.textSecondary),
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

class _AppMenu extends StatelessWidget {
  const _AppMenu({
    required this.app,
    required this.onReport,
    required this.onDisconnect,
    required this.onClose,
  });
  final ZAppDescriptor app;
  final VoidCallback onReport;
  final VoidCallback onDisconnect;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: _AppIcon(app: app, size: 36),
            title: Text(
              app.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (app.developerName != null) 'By ${app.developerName}',
                ?app.trustLabel,
                ?app.resultsLine,
              ].join('\n'),
              style: TextStyle(color: zt.textSecondary),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.flag),
            title: const Text('Report this app'),
            onTap: onReport,
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.plugs),
            title: const Text('Disconnect'),
            onTap: onDisconnect,
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.x),
            title: const Text('Close'),
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}
