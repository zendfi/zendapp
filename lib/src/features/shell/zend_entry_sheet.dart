import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/zend_state.dart';
import '../../design/skeleton_loader.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/recent_contact.dart';
import '../request/payment_request.dart';
import '../request/request_qr_sheet.dart';
import '../send/send_flow_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The Zend entry point — identity-first, per redesign.md §10-16, merged
/// with §12-13 (Send/Request) into a single consolidated screen.
///
/// Originally spec'd as three separate screens (Identity → Identity Found
/// with Send/Request buttons → a dedicated Send or Request screen), this
/// was deliberately merged into one continuous flow: pick a person, then
/// type an amount, then decide Request/Zend/Vibe — closer to "click user
/// → type amount → add note → send or receive → done" than three discrete
/// screen transitions. Reasoning: the amount and note are shared context
/// regardless of direction, and asking the user to declare intent
/// (Send-vs-Request) before they've even typed an amount is a decision
/// made too early — better made at the point of actual commitment. See
/// the redesign.md changelog for the full discussion; this is a
/// deliberate, agreed departure from the original three-screen LOCKED
/// spec, not a silent deviation.
///
///   1. Identity — search by @username or email, or pick from Recent.
///   2. Amount — one screen: avatar/name header, amount keypad, note,
///      then Request / Zend / Vibe.
///   3. Hand-off — Zend delegates to [SendFlowSheet] (PIN/processing/
///      confirmation pipeline unchanged); Request posts directly and
///      shows its own lightweight confirmation inline, since Request has
///      no PIN/signing step to hand off to. Vibe is not yet built —
///      tapping it shows a "coming soon" notice (spec has no Vibe
///      screens; Vibes were previously scoped as Phase 5 of zend-social,
///      not part of this beta round).
Future<void> showZendEntrySheet(
  BuildContext context, {
  String? prefilledRecipient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1.0,
      child: ZendEntrySheet(prefilledRecipient: prefilledRecipient),
    ),
  );
}

class ZendEntrySheet extends StatefulWidget {
  const ZendEntrySheet({super.key, this.prefilledRecipient});

  /// Skips straight to the Amount stage with this identity already
  /// resolved — used when Zend is invoked contextually (e.g. from inside
  /// a Chat or a Person page), where the identity is already known and
  /// shouldn't be re-selected (spec §20/§27: "Context should remove work,
  /// not remove control").
  final String? prefilledRecipient;

  @override
  State<ZendEntrySheet> createState() => _ZendEntrySheetState();
}

enum _EntryStage { identity, amount, requestSuccess }

class _ZendEntrySheetState extends State<ZendEntrySheet> {
  late _EntryStage _stage;
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  bool _submittingRequest = false;
  List<Map<String, dynamic>> _results = [];
  String? _identityError;
  PaymentRequest? _createdRequest;

  // Resolved identity, once established.
  String? _zendtag;
  String? _email;
  String? _displayName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledRecipient != null) {
      _stage = _EntryStage.amount;
      _zendtag = widget.prefilledRecipient;
      _displayName = widget.prefilledRecipient;
    } else {
      _stage = _EntryStage.identity;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  void _onQueryChanged(String value) {
    setState(() {
      _query = value.trim();
      _results = [];
      _identityError = null;
    });
    _debounce?.cancel();
    if (_query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(_query));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final results = await model.walletService.apiClient.searchUsers(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _submitRaw() async {
    final raw = _query;
    if (raw.isEmpty) return;

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (emailRegex.hasMatch(raw)) {
      // Non-Zend recipient by email — spec §15: same identity-first
      // treatment, just without a Zend username at the end of it.
      setState(() {
        _email = raw;
        _displayName = raw.split('@').first;
        _zendtag = null;
        _avatarUrl = null;
        _stage = _EntryStage.amount;
      });
      return;
    }

    final tag = raw.replaceAll('@', '').toLowerCase();
    setState(() => _searching = true);
    try {
      final model = ZendScope.of(context);
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;
      setState(() {
        _zendtag = resolved.zendtag;
        _displayName = resolved.displayName.trim().isNotEmpty ? resolved.displayName : '@${resolved.zendtag}';
        _avatarUrl = resolved.avatarUrl;
        _email = null;
        _searching = false;
        _stage = _EntryStage.amount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _identityError = "We couldn't find anyone with that identity. Check the username or email and try again.";
      });
    }
  }

  void _pickContact(RecentContact c) {
    setState(() {
      _zendtag = c.tag;
      _displayName = c.name.isNotEmpty ? c.name : c.tag;
      _avatarUrl = c.avatarUrl;
      _email = null;
      _stage = _EntryStage.amount;
    });
  }

  void _pickSearchResult(Map<String, dynamic> u) {
    final tag = u['zendtag'] as String? ?? '';
    setState(() {
      _zendtag = tag;
      _displayName = (u['display_name'] as String?)?.trim().isNotEmpty == true
          ? u['display_name'] as String
          : '@$tag';
      _avatarUrl = u['avatar_url'] as String?;
      _email = null;
      _stage = _EntryStage.amount;
    });
  }

  void _changeIdentity() {
    setState(() => _stage = _EntryStage.identity);
  }

  void _confirmZend() {
    if (_amount <= 0) return;
    Navigator.of(context).pop();
    showSendFlowSheet(
      context,
      amount: _amount,
      prefilledRecipient: _zendtag ?? _email,
      prefilledNote: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );
  }

  Future<void> _confirmRequest() async {
    if (_amount <= 0 || _submittingRequest) return;
    final model = ZendScope.of(context);
    setState(() => _submittingRequest = true);
    try {
      final response = await model.walletService.apiClient.createPaymentRequest(
        amountUsdc: _amount,
        description: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        expiresAt: null,
        recipientZendtag: _zendtag,
        recipientEmail: _email,
      );
      final request = PaymentRequest(
        id: response['id'] as String,
        link: response['link_url'] as String,
        amount: (response['amount_usdc'] as num?)?.toDouble() ?? _amount,
        description: _noteController.text.trim(),
        createdAt: DateTime.now(),
        status: PaymentRequestStatus.pending,
        recipientZendtag: response['recipient_zendtag'] as String? ?? _zendtag,
        recipientEmail: response['recipient_email'] as String? ?? _email,
      );
      model.addPaymentRequest(request);
      if (!mounted) return;
      setState(() {
        _submittingRequest = false;
        _createdRequest = request;
        _stage = _EntryStage.requestSuccess;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submittingRequest = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't complete that. Try again.", style: TextStyle(fontFamily: 'Geist'))),
      );
    }
  }

  void _showVibesComingSoon() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final zt = ZendTheme.of(dialogContext);
        return Dialog(
          backgroundColor: zt.bgPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.xxl)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsRegular.gift, size: 36, color: zt.accent),
                const SizedBox(height: 14),
                Text(
                  'Vibes are coming soon!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 18, color: zt.textPrimary),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(label: 'Got it', onPressed: () => Navigator.of(dialogContext).pop()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: ZendSheetHandle()),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: ZendMotion.sheetEnter,
                child: switch (_stage) {
                  _EntryStage.identity => _buildIdentityStage(zt),
                  _EntryStage.amount => _buildAmountStage(zt),
                  _EntryStage.requestSuccess => _buildRequestSuccessStage(zt),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityStage(ZendTheme zt) {
    final model = ZendScope.of(context);
    return Padding(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Zend user_input" — the Z mark sits inline to the left of the
          // field instead of a standalone "Zend" heading above it, so the
          // action and the identity input read as one continuous phrase.
          Container(
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(zt.accent, BlendMode.srcIn),
                    child: Image.asset('assets/icons/zend-icon-navbar.png', width: 20, height: 20, fit: BoxFit.contain),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _submitRaw(),
                    style: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: '@username or email',
                      hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textSecondary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_identityError != null) ...[
            const SizedBox(height: 8),
            Text(
              _identityError!,
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: ZendColors.destructive),
            ),
          ],
          const SizedBox(height: 20),
          if (_query.length >= 2) ..._buildLiveResults(zt) else ..._buildRecent(zt, model.recentContacts),
        ],
      ),
    );
  }

  List<Widget> _buildLiveResults(ZendTheme zt) {
    if (_searching && _results.isEmpty) {
      // Skeleton rows shaped like the real identity rows below them
      // (avatar + two text lines) rather than a spinner — the loading
      // state previews the shape of what's about to appear instead of
      // just signaling "wait".
      return const [SearchUsersSkeleton()];
    }
    if (_results.isEmpty) {
      return [];
    }
    return _results.map((u) {
      final tag = u['zendtag'] as String? ?? '';
      final name = (u['display_name'] as String?)?.trim().isNotEmpty == true ? u['display_name'] as String : tag;
      return _IdentityRow(
        displayName: name,
        subtitle: '@$tag',
        avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
        avatarUrl: u['avatar_url'] as String?,
        onTap: () => _pickSearchResult(u),
      );
    }).toList();
  }

  List<Widget> _buildRecent(ZendTheme zt, List<RecentContact> recent) {
    if (recent.isEmpty) return [];
    return [
      Text(
        'Recent',
        style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
      ),
      const SizedBox(height: 4),
      ...recent.take(6).map((c) => _IdentityRow(
            displayName: c.name.isNotEmpty ? c.name : c.tag,
            subtitle: '@${c.tag}',
            avatarLabel: c.avatarLabel,
            avatarUrl: c.avatarUrl,
            onTap: () => _pickContact(c),
          )),
    ];
  }

  Widget _buildAmountStage(ZendTheme zt) {
    final canAct = _amount > 0;
    return Padding(
      key: const ValueKey('amount'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.prefilledRecipient == null)
                IconButton(
                  onPressed: _changeIdentity,
                  icon: Icon(PhosphorIconsRegular.caretLeft, color: zt.textPrimary, size: 22),
                )
              else
                const SizedBox(width: 48),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(PhosphorIconsRegular.x, color: zt.textSecondary),
              ),
            ],
          ),
          // Identity header, tappable to change person (mirrors the
          // reference screen's avatar+plus).
          GestureDetector(
            onTap: widget.prefilledRecipient == null ? _changeIdentity : null,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ZendAvatar(
                      radius: 28,
                      initials: (_displayName?.isNotEmpty ?? false) ? _displayName![0].toUpperCase() : '?',
                      photoUrl: _avatarUrl,
                    ),
                    if (widget.prefilledRecipient == null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(color: zt.bgPrimary, shape: BoxShape.circle, border: Border.all(color: zt.border)),
                          child: Icon(PhosphorIconsRegular.plus, size: 12, color: zt.accent),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _zendtag != null ? '@$_zendtag' : (_displayName ?? _email ?? ''),
                  style: TextStyle(fontFamily: 'Geist', fontSize: 16, fontWeight: FontWeight.w600, color: zt.textPrimary),
                ),
                if (_email != null)
                  Text(_email!, style: TextStyle(fontFamily: 'Geist', fontSize: 12, color: zt.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 48, fontWeight: FontWeight.w700, color: zt.textPrimary),
            decoration: InputDecoration(
              prefixText: '\$',
              prefixStyle: TextStyle(fontFamily: 'Geist', fontSize: 38, fontWeight: FontWeight.w700, color: zt.textPrimary),
              hintText: '0',
              hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 48, fontWeight: FontWeight.w700, color: zt.textSecondary),
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.pill),
            ),
            child: TextField(
              controller: _noteController,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
              decoration: InputDecoration(
                hintText: "What's this for?",
                hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Request / Zend / Vibe — one row, the decision made at the
          // point of actual commitment, not before the amount exists.
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Opacity(
                  opacity: canAct && !_submittingRequest ? 1 : 0.4,
                  child: OutlineActionButton(
                    label: 'Request',
                    onPressed: canAct && !_submittingRequest ? _confirmRequest : () {},
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: 'Zend',
                  isLoading: _submittingRequest,
                  onPressed: canAct && !_submittingRequest ? _confirmZend : null,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showVibesComingSoon,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: zt.bgSecondary, shape: BoxShape.circle),
                  child: Icon(PhosphorIconsRegular.gift, color: zt.accent, size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestSuccessStage(ZendTheme zt) {
    final request = _createdRequest!;
    final amountStr = request.amount == request.amount.roundToDouble()
        ? '\$${request.amount.toStringAsFixed(0)}'
        : '\$${request.amount.toStringAsFixed(2)}';
    return Padding(
      key: const ValueKey('requestSuccess'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: ZendColors.positive, shape: BoxShape.circle),
            child: const Icon(PhosphorIconsRegular.checkCircle, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          Text('Requested', style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 32, color: zt.textPrimary)),
          const SizedBox(height: 4),
          Text(amountStr, style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 40, color: zt.textPrimary)),
          const SizedBox(height: 8),
          if (request.recipientZendtag != null)
            Text('from @${request.recipientZendtag}', style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textSecondary)),
          if (request.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${request.description}"', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontStyle: FontStyle.italic, color: zt.textSecondary)),
          ],
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Show QR', onPressed: () => showRequestQrSheet(context, request: request))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlineActionButton(label: 'Done', onPressed: () => Navigator.of(context).pop())),
        ],
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.displayName,
    required this.subtitle,
    required this.avatarLabel,
    required this.onTap,
    this.avatarUrl,
  });

  final String displayName;
  final String subtitle;
  final String avatarLabel;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZendRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ZendAvatar(radius: 18, initials: avatarLabel, photoUrl: avatarUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textPrimary)),
                    Text(subtitle, style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: zt.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
