import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/zend_state.dart';
import '../../design/zend_tokens.dart';
import '../../services/zlink_service.dart';

ZlinkService zlinkServiceOf(BuildContext context) {
  final model = ZendScope.of(context);
  return ZlinkService(
    api: model.walletService.apiClient,
    zkLogin: model.zkLoginService,
  );
}

/// Replaces the old "Payment requests" screen: every give link (money you
/// sent out as a link) and ask link (money you're collecting) in one list.
class MyLinksScreen extends StatefulWidget {
  const MyLinksScreen({super.key});

  @override
  State<MyLinksScreen> createState() => _MyLinksScreenState();
}

class _MyLinksScreenState extends State<MyLinksScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _links = [];
  String _filter = 'all';
  final Set<String> _busy = {};

  static const _filters = ['all', 'sent', 'collecting', 'closed'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await zlinkServiceOf(context).myLinks();
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load your links";
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible => _links.where((l) {
    final active = l['status'] == 'active';
    switch (_filter) {
      case 'sent':
        return l['kind'] == 'give' && active;
      case 'collecting':
        return l['kind'] == 'ask' && active;
      case 'closed':
        return !active;
      default:
        return true;
    }
  }).toList();

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _share(Map<String, dynamic> link) async {
    final service = zlinkServiceOf(context);
    String? url;
    if (link['kind'] == 'ask') {
      url = link['url'] as String? ?? zlinkAskUrl(link['id'] as String);
    } else {
      url = (await service.localLink(link['id'] as String))?.url;
    }
    if (url == null) {
      _snack('This link was made on another device. Share it from there.');
      return;
    }
    await Share.share(url);
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _snack('Link copied');
  }

  Future<void> _close(Map<String, dynamic> link) async {
    final id = link['id'] as String;
    final isGive = link['kind'] == 'give';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isGive ? 'Take it back?' : 'Stop collecting?'),
        content: Text(
          isGive
              ? "Whatever hasn't been collected comes back to your balance."
              : 'People will no longer be able to pay this link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(isGive ? 'Take it back' : 'Stop'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy.add(id));
    try {
      final service = zlinkServiceOf(context);
      if (isGive) {
        await service.reclaim(id);
      } else {
        await service.cancelAsk(id);
      }
      _snack(isGive ? 'Money is back in your balance' : 'Link closed');
      await _load();
    } catch (e) {
      _snack(e is ZlinkException ? e.message : 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _filterLabel(String f) => switch (f) {
    'sent' => 'Sent',
    'collecting' => 'Collecting',
    'closed' => 'Closed',
    _ => 'All',
  };

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final visible = _visible;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'My Links',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: Icon(PhosphorIconsRegular.arrowsClockwise, color: zt.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final f = _filters[i];
                  final active = f == _filter;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? zt.accent : zt.bgSecondary,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _filterLabel(f),
                        style: TextStyle(
                          fontFamily: 'Geist',
                          color: active ? ZendColors.textOnDeep : zt.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: zt.textSecondary)))
                  : visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No links yet. Send money to anyone, even if they\'re not on Zend, and it shows up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Geist', color: zt.textSecondary),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _LinkTile(
                          link: visible[i],
                          busy: _busy.contains(visible[i]['id']),
                          onShare: () => _share(visible[i]),
                          onCopy: visible[i]['kind'] == 'ask'
                              ? () => _copy(visible[i]['url'] as String)
                              : null,
                          onClose: () => _close(visible[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.link,
    required this.busy,
    required this.onShare,
    required this.onClose,
    this.onCopy,
  });

  final Map<String, dynamic> link;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onClose;
  final VoidCallback? onCopy;

  String _money() {
    final kobo = link['ngn_quote_kobo'] as num?;
    if (kobo != null) return '₦${(kobo / 100).toStringAsFixed(0)}';
    final usd = (link['amount_usd'] ?? link['max_amount_usd']) as num?;
    return usd == null ? 'Any amount' : '\$${usd.toStringAsFixed(2)}';
  }

  String _subtitle() {
    final isGive = link['kind'] == 'give';
    final status = link['status'] as String;
    if (isGive) {
      final total = link['uses_total'] as int? ?? 1;
      final left = link['uses_left'] as int? ?? 0;
      return switch (status) {
        'claimed' => 'Collected',
        'returned' => 'Taken back',
        'expired' => 'Expired, money returned',
        _ => total > 1 ? '${total - left} of $total collected' : 'Waiting to be collected',
      };
    }
    final paid = link['payments_count'] as int? ?? 0;
    return switch (status) {
      'completed' => 'Done · $paid paid',
      'cancelled' => 'Closed · $paid paid',
      'expired' => 'Expired · $paid paid',
      _ => paid == 0 ? 'Waiting for payments' : '$paid paid',
    };
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final isGive = link['kind'] == 'give';
    final active = link['status'] == 'active';
    final title = (link['memo'] as String?)?.isNotEmpty == true
        ? link['memo'] as String
        : isGive
        ? (link['recipient_hint'] as String? ?? 'Money link')
        : 'Collecting';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: zt.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: zt.bgSecondary,
            child: Icon(
              isGive ? PhosphorIconsRegular.gift : PhosphorIconsRegular.handCoins,
              color: zt.textPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isGive ? 'Sent' : 'Asking'} ${_money()} · $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    color: zt.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (active) ...[
            if (onCopy != null)
              IconButton(icon: Icon(PhosphorIconsRegular.copy, color: zt.textSecondary), onPressed: onCopy),
            IconButton(icon: Icon(PhosphorIconsRegular.shareNetwork, color: zt.textSecondary), onPressed: onShare),
            IconButton(
              tooltip: isGive ? 'Take it back' : 'Stop collecting',
              icon: Icon(PhosphorIconsRegular.arrowUUpLeft, color: zt.textSecondary),
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}
