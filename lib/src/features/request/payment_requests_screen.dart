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
          .cast<Map<String, dynamic>>();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back,
                        color: ZendColors.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Payment requests',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'InstrumentSerif',
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ZendColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: IconButton(
                      icon: const Icon(Icons.refresh,
                          color: ZendColors.textSecondary, size: 20),
                      onPressed: _load,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Filter pills
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final filter in [
                      'all',
                      'pending',
                      'paid',
                      'expired',
                      'cancelled'
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: filter == 'all'
                              ? 'All'
                              : _capitalize(filter),
                          active: _activeFilter == filter,
                          onTap: () {
                            setState(() => _activeFilter = filter);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: ZendColors.border),
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
                                  style: const TextStyle(
                                    fontFamily: 'DMSans',
                                    fontSize: 14,
                                    color: ZendColors.textSecondary,
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
                        : _requests.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: ZendColors.bgSecondary,
                                        borderRadius: BorderRadius.circular(
                                            ZendRadii.xl),
                                      ),
                                      child: const Icon(
                                        Icons.link_off_rounded,
                                        size: 28,
                                        color: ZendColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      _activeFilter == 'all'
                                          ? 'No payment requests yet'
                                          : 'No $_activeFilter requests',
                                      style: const TextStyle(
                                        fontFamily: 'DMSans',
                                        fontSize: 15,
                                        color: ZendColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  itemCount: _requests.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) =>
                                      _RequestCard(
                                    request: _requests[i],
                                    onCopy: () => _copyLink(
                                        _requests[i]['link_url']
                                                as String? ??
                                            ''),
                                    onCancel:
                                        _requests[i]['status'] == 'pending'
                                            ? () => _cancel(
                                                _requests[i]['id']
                                                    as String)
                                            : null,
                                  ),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? ZendColors.accent : ZendColors.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'DMSans',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active
                ? ZendColors.textOnDeep
                : ZendColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onCopy,
    this.onCancel,
  });

  final Map<String, dynamic> request;
  final VoidCallback onCopy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'pending';
    final amount = request['amount_usdc'] as double?;
    final description = request['description'] as String?;
    final link = request['link_url'] as String? ?? '';
    final createdAt = request['created_at'] as String?;

    final statusColor = switch (status) {
      'paid' => ZendColors.positive,
      'expired' || 'cancelled' => ZendColors.textSecondary,
      _ => ZendColors.accent,
    };

    final statusLabel = switch (status) {
      'paid' => 'Paid',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      _ => 'Pending',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZendColors.bgSecondary,
        borderRadius: BorderRadius.circular(ZendRadii.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  amount != null
                      ? '\$${amount.toStringAsFixed(2)}'
                      : 'Pay what you want',
                  style: const TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: ZendColors.textPrimary,
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
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: ZendColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ZendColors.bgPrimary,
                borderRadius: BorderRadius.circular(ZendRadii.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      link,
                      style: const TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 11,
                        color: ZendColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: ZendColors.accent,
                  ),
                ],
              ),
            ),
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatDate(createdAt),
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 11,
                color: ZendColors.textSecondary,
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: ZendColors.border),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onCancel,
              child: const Text(
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
