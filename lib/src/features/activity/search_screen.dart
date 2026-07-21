import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/payment_request_item.dart';
import '../../models/qr_payment_intent.dart';
import '../../navigation/zend_routes.dart';
import '../pools/pool.dart';
import '../pools/pool_detail_screen.dart';
import '../profile/user_profile_screen.dart';
import '../send/qr_payment_sheet.dart';
import 'transaction_receipt_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

/// App-wide search screen.
///
/// Searches across:
/// - Transactions (by name, note, amount)
/// - Payment requests (by zendtag, description)
/// - Pools (by name)
/// - Zend users (by zendtag or display name, via API)
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  String _query = '';
  Timer? _debounce;

  // Remote user search results
  List<Map<String, dynamic>> _remoteUsers = [];
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _remoteUsers = [];
    });

    _debounce?.cancel();
    if (_query.length < 2) return;

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchRemoteUsers(_query);
    });
  }

  Future<void> _searchRemoteUsers(String q) async {
    if (!mounted) return;
    setState(() => _loadingUsers = true);
    try {
      final model = ZendScope.of(context);
      final results = await model.walletService.apiClient.searchUsers(q);
      if (mounted && _query == q) {
        setState(() {
          _remoteUsers = results;
          _loadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);

    final q = _query.toLowerCase();

    // ── Local search ──────────────────────────────────────────────────────────
    final txResults = q.isEmpty ? <dynamic>[] : model.recentTransactions.where((tx) {
      return tx.name.toLowerCase().contains(q) ||
          tx.note.toLowerCase().contains(q) ||
          tx.amount.contains(q);
    }).toList();

    final outboundReqs = q.isEmpty ? <PaymentRequestItem>[] : model.outboundPaymentRequests.where((r) {
      return (r.counterpartyLabel.toLowerCase().contains(q)) ||
          (r.description?.toLowerCase().contains(q) ?? false);
    }).toList();

    final inboundReqs = q.isEmpty ? <PaymentRequestItem>[] : model.inboundPaymentRequests.where((r) {
      return (r.counterpartyLabel.toLowerCase().contains(q)) ||
          (r.description?.toLowerCase().contains(q) ?? false);
    }).toList();

    final poolResults = q.isEmpty ? <Pool>[] : model.pools.where((p) {
      return p.name.toLowerCase().contains(q);
    }).toList();

    final hasLocalResults = txResults.isNotEmpty ||
        outboundReqs.isNotEmpty ||
        inboundReqs.isNotEmpty ||
        poolResults.isNotEmpty;

    final hasResults = hasLocalResults || _remoteUsers.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: zt.bgSecondary,
                        borderRadius: BorderRadius.circular(ZendRadii.pill),
                      ),
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        onChanged: _onQueryChanged,
                        style: TextStyle(
                          fontFamily: 'DMSans',
                          fontSize: 15,
                          color: zt.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search transactions, pools, users…',
                          hintStyle: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 14,
                            color: zt.textSecondary,
                          ),
                          prefixIcon: Icon(SolarIconsBold.magnifier, color: zt.textSecondary, size: 20),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(SolarIconsBold.closeCircle, size: 18, color: zt.textSecondary),
                                  onPressed: () {
                                    _ctrl.clear();
                                    _onQueryChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 14,
                        color: zt.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Results ───────────────────────────────────────────────────────
            Expanded(
              child: _query.isEmpty
                  ? _buildEmptyState(zt)
                  : !hasResults && !_loadingUsers
                      ? _buildNoResults(zt)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            // Remote users
                            if (_remoteUsers.isNotEmpty || _loadingUsers) ...[
                              _SectionHeader(label: 'Users', zt: zt),
                              if (_loadingUsers && _remoteUsers.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(child: ZendLoader(size: 18)),
                                )
                              else
                                ..._remoteUsers.map((u) => _UserTile(
                                      zendtag: u['zendtag'] as String? ?? '',
                                      displayName: u['display_name'] as String? ?? '',
                                      avatarUrl: u['avatar_url'] as String?,
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        pushZendSlide(
                                          context,
                                          UserProfileScreen(
                                            zendtag: u['zendtag'] as String? ?? '',
                                            knownDisplayName: u['display_name'] as String?,
                                            knownAvatarUrl: u['avatar_url'] as String?,
                                          ),
                                        );
                                      },
                                    )),
                              const SizedBox(height: 16),
                            ],

                            // Transactions
                            if (txResults.isNotEmpty) ...[
                              _SectionHeader(label: 'Transactions', zt: zt),
                              ...txResults.map((tx) {
                                final zTx = tx as dynamic;
                                return _SearchTile(
                                  leading: ZendAvatar(
                                    radius: 18,
                                    initials: zTx.avatarLabel as String?,
                                    photoUrl: zTx.avatarUrl as String?,
                                  ),
                                  title: zTx.name as String,
                                  subtitle: zTx.note as String,
                                  trailing: Text(
                                    zTx.amount as String,
                                    style: TextStyle(
                                      fontFamily: 'DMMono',
                                      fontSize: 13,
                                      color: (zTx.amountColor as Color?) ?? zt.textPrimary,
                                    ),
                                  ),
                                  onTap: zTx.entry != null || zTx.bankOrder != null
                                      ? () => showTransactionReceipt(context, tx: zTx)
                                      : null,
                                );
                              }),
                              const SizedBox(height: 16),
                            ],

                            // Payment requests
                            if (outboundReqs.isNotEmpty || inboundReqs.isNotEmpty) ...[
                              _SectionHeader(label: 'Payment Requests', zt: zt),
                              ...[...inboundReqs, ...outboundReqs].map((r) => _SearchTile(
                                    leading: ZendAvatar(
                                      radius: 18,
                                      initials: r.avatarInitial,
                                    ),
                                    title: r.counterpartyLabel,
                                    subtitle: r.description ?? (r.isInbound ? 'Payment request' : 'Sent request'),
                                    trailing: Text(
                                      r.formattedAmount,
                                      style: TextStyle(
                                        fontFamily: 'DMMono',
                                        fontSize: 13,
                                        color: zt.textPrimary,
                                      ),
                                    ),
                                    onTap: r.isInbound && r.isPending
                                        ? () {
                                            Navigator.of(context).pop();
                                            showQrPaymentSheet(
                                              context,
                                              intent: QrPaymentIntent(
                                                zendtag: r.requesterZendtag ?? '',
                                                amountUsdc: r.amountUsdc,
                                                note: r.description,
                                                requestLinkId: r.requestLinkId,
                                              ),
                                            );
                                          }
                                        : null,
                                  )),
                              const SizedBox(height: 16),
                            ],

                            // Pools
                            if (poolResults.isNotEmpty) ...[
                              _SectionHeader(label: 'Pools', zt: zt),
                              ...poolResults.map((pool) => _SearchTile(
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: zt.accentBright.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(SolarIconsBold.usersGroupRounded, size: 18, color: zt.accentBright),
                                    ),
                                    title: pool.name,
                                    subtitle: '\$${pool.gathered.toStringAsFixed(2)} of \$${pool.targetAmount.toStringAsFixed(2)}',
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PoolDetailScreen(pool: pool),
                                        ),
                                      );
                                    },
                                  )),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ZendTheme zt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(SolarIconsBold.magnifier, size: 48, color: zt.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Search transactions, users, pools',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 14,
              color: zt.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(ZendTheme zt) {
    return Center(
      child: Text(
        'No results for "$_query"',
        style: TextStyle(
          fontFamily: 'DMSans',
          fontSize: 14,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.zt});
  final String label;
  final ZendTheme zt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'DMMono',
          fontSize: 10,
          letterSpacing: 1.2,
          color: zt.textSecondary,
        ),
      ),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: zt.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 12,
                        color: zt.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.zendtag,
    required this.displayName,
    this.avatarUrl,
    required this.onTap,
  });

  final String zendtag;
  final String displayName;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final name = displayName.trim().isEmpty ? '@$zendtag' : displayName;
    return _SearchTile(
      leading: ZendAvatar(
        radius: 18,
        initials: name.isNotEmpty ? name[0].toUpperCase() : null,
        photoUrl: avatarUrl,
      ),
      title: name,
      subtitle: '@$zendtag',
      trailing: Icon(SolarIconsBold.altArrowRight, size: 12, color: zt.textSecondary),
      onTap: onTap,
    );
  }
}
