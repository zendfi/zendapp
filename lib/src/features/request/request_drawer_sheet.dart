import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_error_modal.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/sound_service.dart';
import 'payment_request.dart';
import 'request_qr_sheet.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Requesting money — visually mirrors [SendFlowSheet]'s identity-first,
/// amount-entry design (redesign.md §12-13: "Same structure" as Send, just
/// "Request" instead of "Send"). The old full-page form (`_FormStage`,
/// with its own To/Note/Amount field layout) is deactivated — every live
/// caller already supplies an identity via [prefilledRecipient], the same
/// way Send's old recipient-picker page is no longer reachable in
/// practice.
Future<void> showRequestDrawer(
  BuildContext context, {
  double? initialAmount,
  bool amountReadOnly = false,
  String? prefilledRecipient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RequestDrawerSheet(
      initialAmount: initialAmount,
      amountReadOnly: amountReadOnly,
      prefilledRecipient: prefilledRecipient,
    ),
  );
}

// ── Stage enum — mirrors SendStage ────────────────────────────────────────────

enum _RequestStage { amount, loading, success }

// ── Main sheet widget ─────────────────────────────────────────────────────────

class RequestDrawerSheet extends StatefulWidget {
  const RequestDrawerSheet({
    super.key,
    this.initialAmount,
    this.amountReadOnly = false,
    this.prefilledRecipient,
  });

  final double? initialAmount;
  final bool amountReadOnly;

  /// A zendtag already established by an identity-first entry point (the
  /// Zend entry flow — pick identity, then Send/Request). Every live
  /// caller supplies this; the sheet has no independent identity picker
  /// of its own anymore, matching [SendFlowSheet]'s equivalent change.
  final String? prefilledRecipient;

  @override
  State<RequestDrawerSheet> createState() => _RequestDrawerSheetState();
}

class _RequestDrawerSheetState extends State<RequestDrawerSheet> {
  static const Duration _stageTransition = Duration(milliseconds: 180);

  _RequestStage _stage = _RequestStage.amount;

  double _amount = 0;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  // Explicit focus rather than `autofocus` — AnimatedSwitcher keeps the
  // outgoing stage mounted mid-transition, and competing autofocus fields
  // can leave nothing focused at all.
  final FocusNode _amountFocus = FocusNode();

  PaymentRequest? _createdRequest;

  @override
  void initState() {
    super.initState();
    _amount = widget.initialAmount ?? 0;
    if (_amount > 0) _amountController.text = _amount.toStringAsFixed(2);
    if (!widget.amountReadOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  String get _amountFormatted {
    if (_amount == _amount.roundToDouble()) return '\$${_amount.toStringAsFixed(0)}';
    return '\$${_amount.toStringAsFixed(2)}';
  }

  bool get _canCreate => _amount > 0;

  Future<void> _submit() async {
    if (!_canCreate || _stage == _RequestStage.loading) return;
    final model = ZendScope.of(context);
    final tag = widget.prefilledRecipient?.replaceAll('@', '');

    setState(() => _stage = _RequestStage.loading);

    PaymentRequest request;
    try {
      final response = await model.walletService.apiClient.createPaymentRequest(
        amountUsdc: _amount,
        description: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        expiresAt: null,
        recipientZendtag: tag,
        recipientEmail: null,
      );
      request = PaymentRequest(
        id: response['id'] as String,
        link: response['link_url'] as String,
        amount: (response['amount_usdc'] as num?)?.toDouble() ?? _amount,
        description: _noteController.text.trim(),
        createdAt: DateTime.now(),
        expiryDate: null,
        status: PaymentRequestStatus.pending,
        recipientZendtag: response['recipient_zendtag'] as String? ?? tag,
        recipientEmail: response['recipient_email'] as String?,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _RequestStage.amount);
      showZendErrorModal(
        context,
        message: "Couldn't complete that. Try again.",
        onRetry: _submit,
        onDismiss: () => Navigator.of(context).pop(),
      );
      return;
    }

    model.addPaymentRequest(request);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    unawaited(SoundService.playZentSuccess());
    setState(() {
      _stage = _RequestStage.success;
      _createdRequest = request;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final zt = ZendTheme.of(context);

    // Same structure as ZendEntrySheet / zendtag_prompt_sheet: NO Scaffold
    // (its body subtree has bottom viewInsets stripped, so keyboard padding
    // computed inside is always 0), NO fixed height fraction (a fixed
    // height can't be lifted clear of the keyboard). Root-level viewInsets
    // padding, then the coloured surface, then SafeArea, then min-sized
    // content capped to a scrollable max height.
    final maxContentHeight = ((mq.size.height - keyboardInset) * 0.82).clamp(200.0, double.infinity);

    return PopScope(
      canPop: _stage != _RequestStage.loading,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Container(
          decoration: BoxDecoration(
            color: zt.bgPrimary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 14),
                const ZendSheetHandle(),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxContentHeight),
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: _stageTransition,
                      reverseDuration: const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _buildStage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return switch (_stage) {
      _RequestStage.amount => _RequestAmountStage(
          key: const ValueKey('amount'),
          amountController: _amountController,
          amountFocus: _amountFocus,
          amountReadOnly: widget.amountReadOnly,
          noteController: _noteController,
          recipientLabel: widget.prefilledRecipient,
          amountFormatted: _amountFormatted,
          canCreate: _canCreate,
          onAmountChanged: (v) => setState(() => _amount = double.tryParse(v) ?? 0),
          onSubmit: _submit,
        ),
      _RequestStage.loading => const _RequestLoadingStage(key: ValueKey('loading')),
      _RequestStage.success => _RequestSuccessStage(
          key: const ValueKey('success'),
          request: _createdRequest!,
          onDone: () => Navigator.of(context).pop(),
          onShowQr: () => showRequestQrSheet(context, request: _createdRequest!),
        ),
    };
  }
}

// ── Amount Stage — mirrors ZendEntrySheet's Send-amount stage exactly ────────

class _RequestAmountStage extends StatelessWidget {
  const _RequestAmountStage({
    super.key,
    required this.amountController,
    required this.amountFocus,
    required this.amountReadOnly,
    required this.noteController,
    required this.recipientLabel,
    required this.amountFormatted,
    required this.canCreate,
    required this.onAmountChanged,
    required this.onSubmit,
  });

  final TextEditingController amountController;
  final FocusNode amountFocus;
  final bool amountReadOnly;
  final TextEditingController noteController;
  final String? recipientLabel;
  final String amountFormatted;
  final bool canCreate;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Request',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 20, fontWeight: FontWeight.w600, color: zt.textPrimary),
          ),
          if (recipientLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              recipientLabel!.startsWith('@') ? recipientLabel! : '@$recipientLabel',
              style: TextStyle(fontFamily: 'Geist', fontSize: 15, fontWeight: FontWeight.w500, color: zt.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: amountController,
            focusNode: amountFocus,
            readOnly: amountReadOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w700, color: zt.textPrimary),
            decoration: InputDecoration(
              prefixText: '\$',
              prefixStyle: TextStyle(fontFamily: 'Geist', fontSize: 32, fontWeight: FontWeight.w700, color: zt.textPrimary),
              hintText: '0',
              hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 40, fontWeight: FontWeight.w700, color: zt.textSecondary),
              border: InputBorder.none,
            ),
            onChanged: onAmountChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add a note',
              hintStyle: TextStyle(fontFamily: 'Geist', fontSize: 14, color: zt.textSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: canCreate ? 'Request $amountFormatted' : 'Enter an amount',
              onPressed: canCreate ? onSubmit : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading Stage ─────────────────────────────────────────────────────────────

class _RequestLoadingStage extends StatelessWidget {
  const _RequestLoadingStage({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZendLoader(size: 32, color: zt.accent),
          const SizedBox(height: 20),
          Text('Creating request…', style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textSecondary)),
        ],
      ),
    );
  }
}

// ── Success Stage ─────────────────────────────────────────────────────────────

class _RequestSuccessStage extends StatefulWidget {
  const _RequestSuccessStage({super.key, required this.request, required this.onDone, required this.onShowQr});

  final PaymentRequest request;
  final VoidCallback onDone;
  final VoidCallback onShowQr;

  @override
  State<_RequestSuccessStage> createState() => _RequestSuccessStageState();
}

class _RequestSuccessStageState extends State<_RequestSuccessStage> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amount = widget.request.amount;
    final amountStr = amount == amount.roundToDouble() ? '\$${amount.toStringAsFixed(0)}' : '\$${amount.toStringAsFixed(2)}';
    final tag = widget.request.recipientZendtag;
    final note = widget.request.description;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(color: ZendColors.positive, shape: BoxShape.circle),
              child: const Icon(PhosphorIconsRegular.checkCircle, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 20),
          // Spec §14's confirmation pattern, mirrored for Request: "Sent"
          // becomes "Requested" — same lightweight amount / to / note shape.
          Text('Requested', style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 32, color: zt.textPrimary)),
          const SizedBox(height: 4),
          Text(amountStr, style: TextStyle(fontFamily: 'Geist', fontWeight: FontWeight.w700, fontSize: 40, color: zt.textPrimary)),
          const SizedBox(height: 8),
          if (tag != null)
            Text('from @$tag', style: TextStyle(fontFamily: 'Geist', fontSize: 15, color: zt.textSecondary)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"$note"', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Geist', fontSize: 14, fontStyle: FontStyle.italic, color: zt.textSecondary)),
          ],
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Show QR', onPressed: widget.onShowQr)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlineActionButton(label: 'Done', onPressed: widget.onDone)),
        ],
      ),
    );
  }
}
