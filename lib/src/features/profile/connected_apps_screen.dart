import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/appkit_service.dart';
import '../../core/zend_format.dart' show formatNaira;
import '../zapps/zapp_confirm_sheet.dart';
import '../zapps/zapp_sheet.dart';

const _scopeLabels = {
  'profile': 'Name, username and photo',
  'email': 'Your email',
  'wallet_address': 'Can send money straight to you',
  'contacts': 'People you choose to share',
};

/// Apps the user has continued to with Zend, with what each can see and a
/// way to disconnect.
class ConnectedAppsScreen extends StatefulWidget {
  const ConnectedAppsScreen({super.key});
  @override
  State<ConnectedAppsScreen> createState() => _ConnectedAppsScreenState();
}

class _ConnectedAppsScreenState extends State<ConnectedAppsScreen> {
  List<Map<String, dynamic>>? _apps;
  bool _failed = false;

  AppKitService get _svc =>
      AppKitService(ZendScope.of(context).walletService.apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final apps = await _svc.connectedApps();
      if (mounted) {
        setState(() {
          _apps = apps;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setShare(Map<String, dynamic> app, bool value) async {
    final before = app['share_with_friends'] == true;
    setState(() => app['share_with_friends'] = value);
    try {
      await _svc.setShareWithFriends(app['slug'] as String, value);
    } catch (_) {
      if (!mounted) return;
      setState(() => app['share_with_friends'] = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That didn't go through. Try again.")),
      );
    }
  }

  /// Lower an allowance (R6). Raising it is up to the app asking again.
  Future<void> _changeAllowance(Map<String, dynamic> app) async {
    final slug = app['slug'] as String;
    final al = Map<String, dynamic>.from(app['allowance'] as Map);
    try {
      final d = await _svc.descriptor(slug);
      if (!mounted) return;
      final agreed = await confirmZAppAllowance(
        context,
        app: d,
        perPaymentNgn: (al['per_payment_ngn'] as num? ?? 500).toDouble(),
        perDayNgn: (al['per_day_ngn'] as num? ?? 2000).toDouble(),
      );
      if (agreed == null) return;
      await _svc.setAllowance(
        slug,
        perPaymentNgn: agreed.$1,
        perDayNgn: agreed.$2,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That didn't go through. Try again.")),
      );
    }
  }

  Future<void> _turnOffAllowance(Map<String, dynamic> app) async {
    final before = app['allowance'];
    setState(() => app['allowance'] = null);
    try {
      await _svc.revokeAllowance(app['slug'] as String);
    } catch (_) {
      if (!mounted) return;
      setState(() => app['allowance'] = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That didn't go through. Try again.")),
      );
    }
  }

  Future<void> _disconnect(Map<String, dynamic> app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Disconnect ${app['name']}?'),
        content: const Text(
          "It won't be able to see your profile or post for you. Your money isn't affected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.disconnect(app['slug'] as String);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That didn't go through. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    final apps = _apps;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      PhosphorIconsRegular.caretLeft,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connected apps',
                      style: s(26, w: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _failed
                  ? Center(
                      child: Text(
                        "Couldn't load your apps",
                        style: s(14, c: zt.textSecondary),
                      ),
                    )
                  : apps == null
                  ? const Center(child: CircularProgressIndicator())
                  : apps.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Apps you continue to with Zend show up here.',
                          textAlign: TextAlign.center,
                          style: s(14, c: zt.textSecondary),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: apps.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final a = apps[i];
                          final scopes = (a['scopes'] as List? ?? [])
                              .cast<String>();
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: zt.border),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        a['name'] as String,
                                        style: s(15, w: FontWeight.w600),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => openZApp(
                                        context,
                                        a['slug'] as String,
                                      ),
                                      child: const Text('Open'),
                                    ),
                                    TextButton(
                                      onPressed: () => _disconnect(a),
                                      child: const Text('Disconnect'),
                                    ),
                                  ],
                                ),
                                if (a['reviewed'] != true)
                                  Text(
                                    'Not checked by Zend',
                                    style: s(12, c: zt.textSecondary),
                                  ),
                                const SizedBox(height: 6),
                                for (final sc in scopes)
                                  Text(
                                    '• ${_scopeLabels[sc] ?? sc}',
                                    style: s(13, c: zt.textSecondary),
                                  ),
                                if (a['can_post'] == true)
                                  Text(
                                    '• Can post to your feed and chats',
                                    style: s(13, c: zt.textSecondary),
                                  ),
                                if (a['allowance'] is Map) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '• Can pay without asking: up to '
                                    '${formatNaira(((a['allowance'] as Map)['per_payment_ngn'] as num? ?? 0).toDouble())} '
                                    'each time, '
                                    '${formatNaira(((a['allowance'] as Map)['per_day_ngn'] as num? ?? 0).toDouble())} '
                                    'a day',
                                    style: s(13, c: zt.textSecondary),
                                  ),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () => _changeAllowance(a),
                                        child: const Text('Change'),
                                      ),
                                      TextButton(
                                        onPressed: () => _turnOffAllowance(a),
                                        child: const Text('Turn off'),
                                      ),
                                    ],
                                  ),
                                ],
                                if (a['can_post'] == true)
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(
                                      'Share results with friends',
                                      style: s(14),
                                    ),
                                    value: a['share_with_friends'] == true,
                                    onChanged: (v) => _setShare(a, v),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
