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
/// type an amount, then decide Request/Zend/Vibe. See redesign.md §10.1
/// for the rationale — this is an agreed departure from the original
/// three-screen LOCKED spec, not a silent deviation.
///
/// ── Layout contract (do not break) ──────────────────────────────────────
/// This sheet is built on a **bounded** height, and that is deliberate:
///
///   * The sheet gets an explicit height that shrinks by the keyboard
///     inset, so it is always fully on-screen and never covered.
///   * Because the height is bounded, `Expanded` works inside it — each
///     stage can give its scrollable region a real, finite height.
///   * The action buttons live *outside* any scroll view, pinned at the
///     bottom, so they are always visible regardless of scroll position.
///
/// A previous revision made this sheet content-sized (`MainAxisSize.min`
/// inside a `SingleChildScrollView`), which broke three separate things at
/// once and is why the contract above is spelled out:
///   1. The sheet collapsed to a short box instead of opening full length.
///   2. `Row(crossAxisAlignment: stretch)` for the action buttons became
///      illegal — inside an unbounded scroll view its children receive a
///      `tightFor(height: infinity)` constraint, so the buttons rendered
///      as nothing at all.
///   3. That broken RenderFlex poisoned paint/hit-testing for its
///      siblings, leaving the amount and note fields unresponsive.
Future<void> showZendEntrySheet(
  BuildContext context, {
  String? prefilledRecipient,
}) {
  // No `useSafeArea` and no `FractionallySizedBox` wrapper — the sheet
  // computes its own height (keyboard-aware) and applies its own
  // `SafeArea` internally, matching `zendtag_prompt_sheet.dart`, the one
  // OS-keyboard sheet in this app that demonstrably works.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ZendEntrySheet(prefilledRecipient: prefilledRecipient),
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
  // Explicit focus nodes instead of `autofocus: true` on both the search
  // and amount fields. AnimatedSwitcher keeps the outgoing stage mounted
  // during its cross-fade, so with autofocus on both, two TextFields race
  // to claim focus on every stage change and can end up with *neither*
  // focused. Focus is requested explicitly, once, per stage.
  final _searchFocus = FocusNode();
  final _amountFocus = FocusNode();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusForStage());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _searchFocus.dispose();
    _amountFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  /// Single owner of stage transitions, so focus is always handed to
  /// exactly one field per stage — never contested between the outgoing
  /// and incoming stage during the AnimatedSwitcher cross-fade.
  void _goToStage(_EntryStage stage) {
    setState(() => _stage = stage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusForStage());
  }

  void _focusForStage() {
    if (!mounted) return;
    switch (_stage) {
      case _EntryStage.identity:
        _searchFocus.requestFocus();
      case _EntryStage.amount:
        _amountFocus.requestFocus();
      case _EntryStage.requestSuccess:
        // Nothing to type on the confirmation view — drop the keyboard so
        // it doesn't sit over the Show QR / Done actions.
        FocusManager.instance.primaryFocus?.unfocus();
    }
  }

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
      });
      _goToStage(_EntryStage.amount);
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
      });
      _goToStage(_EntryStage.amount);
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
    });
    _goToStage(_EntryStage.amount);
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
    });
    _goToStage(_EntryStage.amount);
  }

  void _changeIdentity() => _goToStage(_EntryStage.identity);

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
      });
      _goToStage(_EntryStage.requestSuccess);
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
                PrimaryButton(label: 'Got it', onPressed: () => Navigator.of(dialogContext).pop()),
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
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;

    // Bounded, keyboard-aware height. Shrinking by the keyboard inset (as
    // well as padding the sheet up by it) is what keeps the whole sheet
    // on-screen instead of having its lower half covered. Everything
    // inside can therefore rely on a finite height — see the layout
    // contract on [showZendEntrySheet].
    final sheetHeight = ((mq.size.height - keyboardInset) * 0.92)
        .clamp(280.0, mq.size.height);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              const ZendSheetHandle(),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: ZendMotion.sheetEnter,
                  child: switch (_stage) {
                    _EntryStage.identity => _buildIdentityStage(zt),
                    _EntryStage.amount => _buildAmountStage(zt),
                    _EntryStage.requestSuccess => _buildRequestSuccessStage(zt),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Identity stage ────────────────────────────────────────────────────
  // Search field pinned at top, results/recents scroll in the remaining
  // (bounded) space via Expanded.

  Widget _buildIdentityStage(ZendTheme zt) {
    final model = ZendScope.of(context);
    return Padding(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    focusNode: _searchFocus,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _submitRaw(),
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textPrimary),
                    decoration: InputDecoration(
                      hintText: '@username or email',
                      hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 16, color: zt.textSecondary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
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
          const SizedBox(height: 16),
          Expanded(child: _buildIdentityResults(zt, model.recentContacts)),
        ],
      ),
    );
  }

  Widget _buildIdentityResults(ZendTheme zt, List<RecentContact> recent) {
    if (_query.length >= 2) {
      if (_searching && _results.isEmpty) {
        // Skeleton rows shaped like the real identity rows rather than a
        // spinner — the loading state previews the shape of what's about
        // to appear instead of just signalling "wait".
        return const SearchUsersSkeleton();
      }
      if (_results.isEmpty) return const SizedBox.shrink();
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final u = _results[i];
          final tag = u['zendtag'] as String? ?? '';
          final name = (u['display_name'] as String?)?.trim().isNotEmpty == true ? u['display_name'] as String : tag;
          return _IdentityRow(
            displayName: name,
            subtitle: '@$tag',
            avatarLabel: name.isNotEmpty ? name[0].toUpperCase() : '?',
            avatarUrl: u['avatar_url'] as String?,
            onTap: () => _pickSearchResult(u),
          );
        },
      );
    }

    if (recent.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: recent.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Recent',
              style: TextStyle(fontFamily: 'Geist', fontSize: 13, fontWeight: FontWeight.w600, color: zt.textSecondary),
            ),
          );
        }
        final c = recent[i - 1];
        return _IdentityRow(
          displayName: c.name.isNotEmpty ? c.name : c.tag,
          subtitle: '@${c.tag}',
          avatarLabel: c.avatarLabel,
          avatarUrl: c.avatarUrl,
          onTap: () => _pickContact(c),
        );
      },
    );
  }

  // ── Amount stage ──────────────────────────────────────────────────────
  // Scrollable middle (identity header + amount + note) with the action
  // row pinned outside the scroll view, so the buttons are always visible
  // and never depend on scroll position.

  Widget _buildAmountStage(ZendTheme zt) {
    final canAct = _amount > 0 && !_submittingRequest;
    return Padding(
      key: const ValueKey('amount'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Identity header, tappable to change person.
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
                                  decoration: BoxDecoration(
                                    color: zt.bgPrimary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: zt.border),
                                  ),
                                  child: Icon(PhosphorIconsRegular.arrowsLeftRight, size: 12, color: zt.accent),
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
                  const SizedBox(height: 20),
                  // The amount reads as one tight unit: a smaller "$" glyph
                  // sits immediately to the left of the number instead of
                  // via InputDecoration.prefixText, which pads the prefix
                  // away from the figure and (with textAlign.center) leaves
                  // a visible "$    1" gap. The Row is centered and the
                  // field shrink-wraps its content (IntrinsicWidth) so the
                  // "$" always hugs the digits.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '\$',
                        style: TextStyle(fontFamily: 'Geist', fontSize: 28, fontWeight: FontWeight.w700, color: zt.textPrimary),
                      ),
                      const SizedBox(width: 2),
                      IntrinsicWidth(
                        child: TextField(
                          controller: _amountController,
                          focusNode: _amountFocus,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.left,
                          style: TextStyle(fontFamily: 'Geist', fontSize: 48, fontWeight: FontWeight.w700, color: zt.textPrimary),
                          decoration: InputDecoration(
                            hintText: '0',
                            hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 48, fontWeight: FontWeight.w700, color: zt.textSecondary),
                            // Explicitly borderless/unfilled — the global
                            // InputDecorationTheme fills and pill-rounds inputs
                            // by default, which would draw a capsule around the
                            // big amount figure.
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── Note field — pinned above the action row ──
          // Lives outside the scroll view (a fixed-height, non-Expanded
          // sibling) so it always sits directly above the buttons, matching
          // the reference. A smaller, squarer radius reads as a rounded
          // rectangle input rather than a capsule.
          Container(
            decoration: BoxDecoration(
              color: zt.bgSecondary,
              borderRadius: BorderRadius.circular(ZendRadii.md),
            ),
            child: TextField(
              controller: _noteController,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
              decoration: InputDecoration(
                hintText: "What's this for?",
                hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Action row — pinned outside the scroll view ──
          // NOTE: no `crossAxisAlignment: stretch` here. Each child sizes
          // itself to an explicit height instead; `stretch` would force a
          // tightFor(height:) constraint that breaks these buttons if this
          // row ever ends up in unbounded vertical space again.
          Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: canAct ? 1 : 0.4,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: canAct ? _confirmRequest : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: zt.textPrimary,
                        side: BorderSide(color: zt.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.pill)),
                      ),
                      child: const Text(
                        'Request',
                        style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: canAct ? _confirmZend : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: zt.accent,
                      foregroundColor: ZendColors.textOnDeep,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZendRadii.pill)),
                    ),
                    child: _submittingRequest
                        ? const ZendLoader(size: 20, strokeWidth: 2, color: ZendColors.textOnDeep)
                        : const Text(
                            'Pay',
                            style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                  ),
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

  // ── Request confirmation ──────────────────────────────────────────────

  Widget _buildRequestSuccessStage(ZendTheme zt) {
    final request = _createdRequest!;
    final amountStr = request.amount == request.amount.roundToDouble()
        ? '\$${request.amount.toStringAsFixed(0)}'
        : '\$${request.amount.toStringAsFixed(2)}';
    return SingleChildScrollView(
      key: const ValueKey('requestSuccess'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 64,
            height: 64,
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
            Text(
              '"${request.description}"',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontStyle: FontStyle.italic, color: zt.textSecondary),
            ),
          ],
          const SizedBox(height: 28),
          PrimaryButton(label: 'Show QR', onPressed: () => showRequestQrSheet(context, request: request)),
          const SizedBox(height: 12),
          OutlineActionButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
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
