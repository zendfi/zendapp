import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';

class PaymentRequestsScreen extends StatefulWidget {
  const PaymentRequestsScreen({super.key});

  @override
  State<PaymentRequestsScreen> createState() => _PaymentRequestsScreenState();
}

class _PaymentRequestsScreenState extends State<PaymentRequestsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];
  String _activeFilter = 'all';

  static const _filters = ['all', 'pending', 'paid', 'expired', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final model = ZendScope.of(context);
      final status = _activeFilter == 'all' ? null : _activeFilter;
      final data = await model.walletService.apiClient.getPaymentRequests(
        status: status,
      );
      final list = (data['requests'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          // Only show requests with a fixed amount — no PWYW
          .where((r) => r['amount_usdc'] != null)
          .toList();
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load payment requests';
        _loading = false;
      });
    }
  }

  Future<void> _cancel(String id) async {
    try {
      final model = ZendScope.of(context);
      await model.walletService.apiClient.cancelPaymentRequest(id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel request')),
        );
      }
    }
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _filterLabel(String f) =>
      f == 'all' ? 'All' : f[0].toUpperCase() + f.substring(1);

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header — matches activity screen layout ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  // Back button sits left, same weight as activity icons
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_back, color: zt.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Payment requests',
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: Icon(Icons.refresh, color: zt.textSecondary),
                  ),
                ],
              ),
            ),

            // ── Filter pills — identical structure to activity screen ──
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: _filters.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final filter = _filters[i];
                  final active = _activeFilter == filter;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _activeFilter = filter);
                      _load();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? zt.accent : zt.bgSecondary,
                        borderRadius:
                            BorderRadius.circular(ZendRadii.pill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _filterLabel(filter),
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          color: active
                              ? ZendColors.textOnDeep
                              : zt.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Content ──
            Expanded(
              child: _loading
                  ? const Center(child: ZendLoader())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                style: TextStyle(
                                  fontFamily: 'DMSans',
                                  fontSize: 14,
                                  color: zt.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ZendScrollPage(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 24),
                              child: _requests.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 48),
                                      child: Center(
                                        child: Text(
                                          _activeFilter == 'all'
                                              ? 'No payment requests yet'
                                              : 'No ${_filterLabel(_activeFilter).toLowerCase()} requests',
                                          style: TextStyle(
                                            fontFamily: 'DMSans',
                                            fontSize: 14,
                                            color: zt.textSecondary,
                                          ),
                                        ),
                                      ),
                                    )
                                  // Single grouped container — same as activity screen
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: zt.bgSecondary,
                                        borderRadius:
                                            BorderRadius.circular(24),
                                      ),
                                      child: Column(
                                        children: [
                                          for (var i = 0;
                                              i < _requests.length;
                                              i++) ...[
                                            _RequestTile(
                                              request: _requests[i],
                                              onCopy: () => _copyLink(
                                                  _requests[i]['link_url']
                                                          as String? ??
                                                      ''),
                                              onCancel: _requests[i]
                                                          ['status'] ==
                                                      'pending'
                                                  ? () => _cancel(
                                                      _requests[i]['id']
                                                          as String)
                                                  : null,
                                            ),
                                            if (i < _requests.length - 1)
                                              Divider(
                                                  color: zt.border,
                                                  height: 1),
                                          ],
                                        ],
                                      ),
                                    ),
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

/// A single payment request row — styled like an activity tile.
class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onCopy,
    this.onCancel,
  });

  final Map<String, dynamic> request;
  final VoidCallback onCopy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    final status = request['status'] as String? ?? 'pending';
    final amount = (request['amount_usdc'] as num?)?.toDouble();
    final description = request['description'] as String?;
    final link = request['link_url'] as String? ?? '';
    final createdAt = request['created_at'] as String?;

    final statusColor = switch (status) {
      'paid' => ZendColors.positive,
      'expired' || 'cancelled' => zt.textSecondary,
      _ => zt.accent,
    };

    final statusLabel = switch (status) {
      'paid' => 'Paid',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      _ => 'Pending',
    };

    // Amount string — always fixed since we filter out PWYW
    final amountStr = amount != null
        ? '\$${amount.toStringAsFixed(2)}'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: amount + status badge ──
          Row(
            children: [
              Expanded(
                child: Text(
                  amountStr,
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 22,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    color: zt.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZendRadii.pill),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          // ── Description ──
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              description,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: zt.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 10),

          // ── Link row ──
          GestureDetector(
            onTap: onCopy,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    link,
                    style: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 11,
                      color: zt.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.copy_outlined, size: 14, color: zt.accent),
              ],
            ),
          ),

          // ── Date + cancel ──
          if (createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _formatDate(createdAt),
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: zt.textSecondary,
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onCancel,
              child: Text(
                'Cancel request',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}
