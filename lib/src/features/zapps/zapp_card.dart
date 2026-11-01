import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/appkit_service.dart';
import 'zapp_sheet.dart';

/// Core-owned renderer for ZApp templates (result, invite, status).
/// The app supplies only text, emoji, media and buttons; status comes from
/// the live interaction. Unknown templates fall back to a plain card.
class ZAppCard extends StatefulWidget {
  const ZAppCard({super.key, required this.card});

  /// `{app: slug|{slug,name}, app_name?, template, slots, interaction_id}`
  final Map<String, dynamic> card;

  @override
  State<ZAppCard> createState() => _ZAppCardState();
}

class _ZAppCardState extends State<ZAppCard> {
  String? _state;
  Timer? _poll;

  String get _slug {
    final a = widget.card['app'];
    return a is Map ? a['slug'] as String : a as String;
  }

  String get _appName {
    final a = widget.card['app'];
    return (a is Map ? a['name'] : widget.card['app_name']) as String? ?? 'App';
  }

  @override
  void initState() {
    super.initState();
    _state = widget.card['state'] as String?;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    // Interactions also push `app_interaction` events; polling is the fallback.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final id = widget.card['interaction_id'] as String?;
    if (id == null || !mounted) return;
    try {
      final i = await AppKitService(
        ZendScope.of(context).walletService.apiClient,
      ).getInteraction(id);
      if (mounted) setState(() => _state = i['state'] as String?);
    } catch (_) {}
  }

  Future<void> _press(Map<String, dynamic> b) async {
    final interaction = widget.card['interaction_id'] as String?;
    switch (b['action']) {
      case 'open_sheet':
        await openZApp(
          context,
          _slug,
          path: b['path'] as String? ?? '/',
          query: interaction == null ? null : {'interaction': interaction},
        );
      case 'start_interaction':
        // Opens at the app's entry; `from` lets the app reuse the same people.
        await openZApp(
          context,
          _slug,
          query: {'start': b['type'] as String? ?? '', 'from': ?interaction},
        );
      case 'open_url':
        final u = Uri.tryParse(b['url'] as String? ?? '');
        if (u != null) {
          await openZApp(
            context,
            _slug,
            path: u.hasQuery ? '${u.path}?${u.query}' : u.path,
          );
        }
    }
    _refresh();
  }

  static String _stateLabel(String s) => switch (s) {
    'sent' => 'Waiting',
    'accepted' => 'Accepted',
    'in_progress' => 'In progress',
    'resolved' => 'Done',
    'expired' => 'Expired',
    _ => s.replaceAll('_', ' '),
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final template = widget.card['template'] as String?;
    final slots = Map<String, dynamic>.from(widget.card['slots'] as Map? ?? {});
    final known = const {'result', 'invite', 'status'}.contains(template);
    TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(
          fontFamily: 'Geist',
          fontSize: size,
          fontWeight: w,
          color: c ?? zt.textPrimary,
        );
    final buttons = known
        ? (slots['buttons'] as List? ?? [])
              .cast<Map>()
              .map(Map<String, dynamic>.from)
              .toList()
        : <Map<String, dynamic>>[];
    final finished = _state == 'resolved' || _state == 'expired';
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: zt.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: zt.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.squaresFour,
                size: 13,
                color: zt.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _appName,
                  style: s(11, w: FontWeight.w600, c: zt.textSecondary),
                ),
              ),
              if (_state != null && template != 'result')
                Text(_stateLabel(_state!), style: s(11, c: zt.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if (known && slots['media'] is String) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                slots['media'] as String,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            known
                ? [slots['emoji'], slots['title']].whereType<String>().join(' ')
                : 'Open in Zend to see this',
            style: s(15, w: FontWeight.w600),
          ),
          if (known && slots['subtitle'] is String) ...[
            const SizedBox(height: 2),
            Text(
              slots['subtitle'] as String,
              style: s(13, c: zt.textSecondary),
            ),
          ],
          if (buttons.isNotEmpty || !known) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (!known)
                  OutlinedButton(
                    onPressed: () => openZApp(context, _slug),
                    child: const Text('Open'),
                  ),
                for (final b in buttons)
                  // Invites stop being actionable once the interaction is finished.
                  OutlinedButton(
                    onPressed: template == 'invite' && finished
                        ? null
                        : () => _press(b),
                    child: Text(b['label'] as String? ?? 'Open'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
