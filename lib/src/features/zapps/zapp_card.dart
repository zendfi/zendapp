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
  const ZAppCard({super.key, required this.card, this.inBubble = false});

  /// `{app: slug|{slug,name}, app_name?, template, slots, interaction_id}`
  final Map<String, dynamic> card;

  /// Drawn inside a DM bubble: the bubble supplies the surface, so the
  /// card drops its own box and tightens up.
  final bool inBubble;

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
    final bubble = widget.inBubble;
    return Container(
      constraints: bubble ? null : const BoxConstraints(maxWidth: 320),
      padding: bubble ? EdgeInsets.zero : const EdgeInsets.all(14),
      decoration: bubble
          ? null
          : BoxDecoration(
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
          SizedBox(height: bubble ? 4 : 8),
          if (known && slots['media'] is String) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                slots['media'] as String,
                height: bubble ? 110 : 140,
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
            style: s(bubble ? 14.5 : 15, w: FontWeight.w600),
            maxLines: bubble ? 3 : null,
            overflow: bubble ? TextOverflow.ellipsis : null,
          ),
          if (known && slots['subtitle'] is String) ...[
            const SizedBox(height: 2),
            Text(
              slots['subtitle'] as String,
              style: s(13, c: zt.textSecondary),
            ),
          ],
          // Set only by Zend's server after its own check (R9). Never shown
          // as a warning when missing: no badge just means nothing to show.
          if (template == 'result' && slots['checked'] is Map) ...[
            const SizedBox(height: 6),
            Semantics(
              button: true,
              label: 'Result checked. Tap to see what was checked.',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showChecked(
                  context,
                  _appName,
                  Map<String, dynamic>.from(slots['checked'] as Map),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'Result checked ✓',
                    style: s(12, w: FontWeight.w600, c: zt.moneyIn),
                  ),
                ),
              ),
            ),
          ],
          if (buttons.isNotEmpty || !known) ...[
            SizedBox(height: bubble ? 8 : 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!known)
                  OutlinedButton(
                    style: bubble ? _compact(zt) : null,
                    onPressed: () => openZApp(context, _slug),
                    child: const Text('Open'),
                  ),
                for (final b in buttons)
                  // Invites stop being actionable once the interaction is finished.
                  OutlinedButton(
                    style: bubble ? _compact(zt) : null,
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

/// Small pill buttons for cards inside chat bubbles.
ButtonStyle _compact(ZendTheme zt) => OutlinedButton.styleFrom(
  minimumSize: const Size(0, 34),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.compact,
  foregroundColor: zt.textPrimary,
  side: BorderSide(color: zt.border),
  shape: const StadiumBorder(),
  textStyle: const TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    fontWeight: FontWeight.w600,
  ),
);

/// What "Result checked ✓" means, in plain words (R9.3).
void _showChecked(BuildContext context, String app, Map<String, dynamic> c) {
  final zt = ZendTheme.of(context);
  final draws = (c['draws'] as List? ?? const []).length;
  TextStyle s(double size, {FontWeight w = FontWeight.w400, Color? col}) =>
      TextStyle(
        fontFamily: 'Geist',
        fontSize: size,
        fontWeight: w,
        color: col ?? zt.textPrimary,
      );
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: zt.bgPrimary,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Result checked ✓', style: s(18, w: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              draws == 1
                  ? 'The chance behind this result was drawn by Zend, not by $app '
                        'or anyone playing. It was recorded when it happened, and '
                        'nobody can draw it again or change it.'
                  : 'The $draws chances behind this result were drawn by Zend, not '
                        'by $app or anyone playing. Each was recorded when it '
                        'happened, and nobody can draw them again or change them.',
              style: s(15),
            ),
            const SizedBox(height: 10),
            Text(
              'Zend checked this when the card was posted. How $app '
              'turns the draw into a winner is up to $app.',
              style: s(13, col: zt.textSecondary),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
