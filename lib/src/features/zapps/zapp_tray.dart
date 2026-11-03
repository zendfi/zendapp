import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_modal.dart';
import '../../design/zend_tokens.dart';
import '../../services/appkit_service.dart';
import 'zapp_sheet.dart';

/// Chat "+" → Apps. Lists chat actions from apps the user has connected.
/// Picking one starts that action's interaction with the person in this chat,
/// then opens the app's sheet on it.
Future<void> showZAppTray(
  BuildContext context, {
  required String counterpartyUserId,
}) {
  return showZendModalSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _Tray(counterpartyUserId: counterpartyUserId),
  );
}

class _TrayAction {
  _TrayAction(this.app, this.action);
  final ZAppDescriptor app;
  final Map<String, dynamic> action;
}

class _Tray extends StatefulWidget {
  const _Tray({required this.counterpartyUserId});

  /// The other person in this chat. Sent as `chat:<id>` so it works even
  /// for people who haven't picked a username yet.
  final String counterpartyUserId;
  @override
  State<_Tray> createState() => _TrayState();
}

class _TrayState extends State<_Tray> {
  List<_TrayAction>? _actions;
  String? _error;
  bool _starting = false;

  AppKitService get _svc =>
      AppKitService(ZendScope.of(context).walletService.apiClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final connected = await _svc.connectedApps();
      final out = <_TrayAction>[];
      for (final c in connected) {
        try {
          final d = await _svc.descriptor(c['slug'] as String);
          for (final a in d.chatActions) {
            out.add(_TrayAction(d, a));
          }
        } catch (_) {
          /* suspended or removed app: skip */
        }
      }
      if (mounted) setState(() => _actions = out);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load your apps");
    }
  }

  Future<void> _start(_TrayAction t) async {
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    try {
      final path = t.action['sheet'] as String? ?? '/';
      final type = t.action['interaction'] as String?;
      Map<String, String>? query;
      if (type != null) {
        final i = await _svc.createInteraction(t.app.slug, {
          'type': type,
          'participants': ['chat:${widget.counterpartyUserId}'],
        });
        query = {'interaction': i['id'] as String};
      }
      navigator.pop();
      if (rootContext.mounted) {
        await openZApp(rootContext, t.app.slug, path: path, query: query);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("That didn't go through. Try again.")),
      );
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final actions = _actions;
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Apps', style: s(20, w: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: s(14, c: zt.textSecondary))
            else if (actions == null || _starting)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (actions.isEmpty)
              Text(
                'Apps you connect to show up here.',
                style: s(14, c: zt.textSecondary),
              )
            else
              for (final a in actions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: zt.bgSecondary,
                    backgroundImage: a.app.iconUrl != null
                        ? NetworkImage(a.app.iconUrl!)
                        : null,
                    child: a.app.iconUrl == null
                        ? Icon(
                            PhosphorIconsRegular.squaresFour,
                            color: zt.textSecondary,
                          )
                        : null,
                  ),
                  title: Text(
                    a.action['label'] as String? ?? a.app.name,
                    style: s(15, w: FontWeight.w600),
                  ),
                  subtitle: Text(
                    a.app.trustLabel ?? a.app.name,
                    style: s(12, c: zt.textSecondary),
                  ),
                  onTap: () => _start(a),
                ),
          ],
        ),
      ),
    );
  }
}
