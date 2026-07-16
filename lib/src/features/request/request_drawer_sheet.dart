import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_avatar.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/sound_service.dart';
import 'payment_request.dart';
import 'request_qr_sheet.dart';
import 'request_utils.dart';

Future<void> showRequestDrawer(
  BuildContext context, {
  double? initialAmount,
  bool amountReadOnly = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 1.0,
      child: RequestDrawerSheet(
        initialAmount: initialAmount,
        amountReadOnly: amountReadOnly,
      ),
    ),
  );
}

// ── Stage enum — mirrors SendStage pattern ────────────────────────────────────

enum _RequestStage { form, loading, success }

// ── Main sheet widget ─────────────────────────────────────────────────────────

class RequestDrawerSheet extends StatefulWidget {
  const RequestDrawerSheet({
    super.key,
    this.initialAmount,
    this.amountReadOnly = false,
  });

  final double? initialAmount;
  final bool amountReadOnly;

  @override
  State<RequestDrawerSheet> createState() => _RequestDrawerSheetState();
}

class _RequestDrawerSheetState extends State<RequestDrawerSheet> {
  static const int _noteMaxLength = 140;
  static const Duration _stageTransition = Duration(milliseconds: 180);
  static const Duration _sheetResize = Duration(milliseconds: 220);

  _RequestStage _stage = _RequestStage.form;

  // Form state
  double _amount = 0;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _toController = TextEditingController();

  String _toValue = '';
  bool _resolving = false;
  String? _resolvedZendtag;
  String? _resolvedDisplayName;
  String? _resolvedAvatarUrl;
  String? _recipientEmail;
  String? _resolveError;
  Timer? _debounceTimer;

  PaymentRequest? _createdRequest;

  @override
  void initState() {
    super.initState();
    _amount = widget.initialAmount ?? 0;
    if (_amount > 0) _amountController.text = _amount.toStringAsFixed(2);
    _toController.addListener(() {});
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _amountController.dispose();
    _noteController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String get _amountFormatted {
    if (_amount == _amount.roundToDouble()) return '\$${_amount.toStringAsFixed(0)}';
    return '\$${_amount.toStringAsFixed(2)}';
  }

  bool get _canCreate => _amount > 0;

  bool get _hasValidRecipient => _resolvedZendtag != null || _recipientEmail != null;

  void _onToChanged(String v) {
    setState(() {
      _toValue = v;
      _resolvedZendtag = null;
      _resolvedDisplayName = null;
      _resolvedAvatarUrl = null;
      _recipientEmail = null;
      _resolveError = null;
    });
    _debounceTimer?.cancel();
    if (v.trim().isEmpty) return;

    final trimmed = v.trim();
    if (trimmed.contains('@') && trimmed.contains('.') && !trimmed.startsWith('@')) {
      // Looks like an email
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (emailRegex.hasMatch(trimmed)) {
        setState(() => _recipientEmail = trimmed);
      }
      return;
    }

    // Zendtag — strip @ prefix and resolve
    final tag = trimmed.replaceAll('@', '').toLowerCase();
    if (tag.isEmpty) return;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () => _resolveTag(tag));
  }

  Future<void> _resolveTag(String tag) async {
    if (!mounted) return;
    final model = ZendScope.of(context);
    if (tag == model.currentZendtag) {
      setState(() => _resolveError = "Can't request from yourself");
      return;
    }
    setState(() { _resolving = true; _resolveError = null; });
    try {
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;
      setState(() {
        _resolvedZendtag = resolved.zendtag;
        _resolvedDisplayName = resolved.displayName.trim().isNotEmpty ? resolved.displayName : '@${resolved.zendtag}';
        _resolvedAvatarUrl = resolved.avatarUrl;
        _resolving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _resolving = false; });
    }
  }

  Future<void> _submit() async {
    if (!_canCreate || _stage == _RequestStage.loading) return;
    final model = ZendScope.of(context);

    setState(() => _stage = _RequestStage.loading);

    PaymentRequest request;
    try {
      final response = await model.walletService.apiClient.createPaymentRequest(
        amountUsdc: _amount,
        description: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        expiresAt: null,
        recipientZendtag: _resolvedZendtag,
        recipientEmail: _recipientEmail,
      );
      request = PaymentRequest(
        id: response['id'] as String,
        link: response['link_url'] as String,
        amount: (response['amount_usdc'] as num?)?.toDouble() ?? _amount,
        description: _noteController.text.trim(),
        createdAt: DateTime.now(),
        expiryDate: null,
        status: PaymentRequestStatus.pending,
        recipientZendtag: response['recipient_zendtag'] as String? ?? _resolvedZendtag,
        recipientEmail: response['recipient_email'] as String? ?? _recipientEmail,
      );
    } catch (_) {
      final requestId = generateRequestId();
      request = PaymentRequest(
        id: requestId,
        link: buildRequestLink(model.username, requestId),
        amount: _amount,
        description: _noteController.text.trim(),
        createdAt: DateTime.now(),
        expiryDate: null,
        status: PaymentRequestStatus.pending,
        recipientZendtag: _resolvedZendtag,
        recipientEmail: _recipientEmail,
      );
    }

    model.addPaymentRequest(request);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    unawaited(SoundService.playZentSuccess());
    setState(() { _stage = _RequestStage.success; _createdRequest = request; });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    final double heightFraction = switch (_stage) {
      _RequestStage.form    => 1.0,
      _RequestStage.loading => 0.45,
      _RequestStage.success => 0.55,
    };

    return PopScope(
      canPop: _stage != _RequestStage.loading,
      child: AnimatedContainer(
        duration: _sheetResize,
        curve: Curves.easeOutCubic,
        height: screenHeight * heightFraction,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            const ZendSheetHandle(),
            const SizedBox(height: 8),
            Expanded(
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
                child: RepaintBoundary(child: _buildStage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    return switch (_stage) {
      _RequestStage.form    => _FormStage(
          key: const ValueKey('form'),
          amountController: _amountController,
          amountReadOnly: widget.amountReadOnly,
          noteController: _noteController,
          noteMaxLength: _noteMaxLength,
          toController: _toController,
          toValue: _toValue,
          resolving: _resolving,
          resolvedZendtag: _resolvedZendtag,
          resolvedDisplayName: _resolvedDisplayName,
          resolvedAvatarUrl: _resolvedAvatarUrl,
          recipientEmail: _recipientEmail,
          resolveError: _resolveError,
          canCreate: _canCreate,
          hasValidRecipient: _hasValidRecipient,
          amountFormatted: _amountFormatted,
          onAmountChanged: (v) => setState(() => _amount = double.tryParse(v) ?? 0),
          onToChanged: _onToChanged,
          onSubmit: _submit,
        ),
      _RequestStage.loading => _LoadingStage(key: const ValueKey('loading')),
      _RequestStage.success => _SuccessStage(
          key: const ValueKey('success'),
          request: _createdRequest!,
          onDone: () => Navigator.of(context).pop(),
          onShowQr: () => showRequestQrSheet(context, request: _createdRequest!),
        ),
    };
  }
}

// ── Form Stage ────────────────────────────────────────────────────────────────

class _FormStage extends StatelessWidget {
  const _FormStage({
    super.key,
    required this.amountController,
    required this.amountReadOnly,
    required this.noteController,
    required this.noteMaxLength,
    required this.toController,
    required this.toValue,
    required this.resolving,
    required this.resolvedZendtag,
    required this.resolvedDisplayName,
    required this.resolvedAvatarUrl,
    required this.recipientEmail,
    required this.resolveError,
    required this.canCreate,
    required this.hasValidRecipient,
    required this.amountFormatted,
    required this.onAmountChanged,
    required this.onToChanged,
    required this.onSubmit,
  });

  final TextEditingController amountController;
  final bool amountReadOnly;
  final TextEditingController noteController;
  final int noteMaxLength;
  final TextEditingController toController;
  final String toValue;
  final bool resolving;
  final String? resolvedZendtag;
  final String? resolvedDisplayName;
  final String? resolvedAvatarUrl;
  final String? recipientEmail;
  final String? resolveError;
  final bool canCreate;
  final bool hasValidRecipient;
  final String amountFormatted;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onToChanged;
  final VoidCallback onSubmit;

  String get _buttonLabel {
    if (!hasValidRecipient) return 'Request $amountFormatted';
    if (resolvedZendtag != null) return 'Request from @$resolvedZendtag';
    return 'Send to $recipientEmail';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 50;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            bottom: 72 + (keyboardOpen ? keyboardHeight : 0),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  Text(
                    'Request $amountFormatted',
                    style: TextStyle(
                      fontFamily: 'InstrumentSerif',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Amount field (editable unless read-only) ──
                  if (!amountReadOnly) ...[
                    _FieldRow(
                      label: r'$',
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        onChanged: onAmountChanged,
                        style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: TextStyle(color: zt.textSecondary),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(color: zt.border, height: 1),
                    const SizedBox(height: 4),
                  ],

                  // ── To field ──
                  _FieldRow(
                    label: 'To',
                    child: TextField(
                      controller: toController,
                      onChanged: onToChanged,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary),
                      decoration: InputDecoration(
                        hintText: '@username or email',
                        hintStyle: TextStyle(color: zt.textSecondary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        suffixIconConstraints: const BoxConstraints(maxWidth: 24, maxHeight: 24),
                        suffixIcon: resolving
                            ? ZendLoader(size: 16, strokeWidth: 1.5, color: zt.textSecondary)
                            : (resolvedZendtag != null || recipientEmail != null)
                                ? Icon(Icons.check_circle_outline, size: 16, color: zt.accentBright)
                                : null,
                      ),
                    ),
                  ),

                  // Resolved name or error
                  if (resolvedDisplayName != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Row(
                        children: [
                          if (resolvedAvatarUrl != null) ...[
                            ZendAvatar(radius: 10, photoUrl: resolvedAvatarUrl, initials: resolvedDisplayName![0].toUpperCase()),
                            const SizedBox(width: 6),
                          ],
                          Text(resolvedDisplayName!, style: TextStyle(fontFamily: 'DMMono', fontSize: 12, color: zt.accentBright)),
                        ],
                      ),
                    )
                  else if (resolveError != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Text(resolveError!, style: const TextStyle(fontFamily: 'DMMono', fontSize: 12, color: ZendColors.destructive)),
                    ),

                  const SizedBox(height: 4),
                  Divider(color: zt.border, height: 1),
                  const SizedBox(height: 4),

                  // ── Note field ──
                  _FieldRow(
                    label: 'Note',
                    child: TextField(
                      controller: noteController,
                      maxLength: noteMaxLength,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'optional',
                        hintStyle: TextStyle(color: zt.textSecondary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),
                  Divider(color: zt.border, height: 1),
                ],
              ),
            ),
          ),

          // ── Floating request button ──
          Positioned(
            left: 20,
            right: 20,
            bottom: (keyboardOpen ? keyboardHeight : 0) + 16,
            child: PrimaryButton(
              label: _buttonLabel,
              onPressed: canCreate ? onSubmit : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading Stage ─────────────────────────────────────────────────────────────

class _LoadingStage extends StatelessWidget {
  const _LoadingStage({super.key});

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZendLoader(size: 32, color: zt.accent),
          const SizedBox(height: 20),
          Text('Creating request…', style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary)),
        ],
      ),
    );
  }
}

// ── Success Stage ─────────────────────────────────────────────────────────────

class _SuccessStage extends StatefulWidget {
  const _SuccessStage({super.key, required this.request, required this.onDone, required this.onShowQr});

  final PaymentRequest request;
  final VoidCallback onDone;
  final VoidCallback onShowQr;

  @override
  State<_SuccessStage> createState() => _SuccessStageState();
}

class _SuccessStageState extends State<_SuccessStage> with SingleTickerProviderStateMixin {
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

  String _headline() {
    if (widget.request.recipientZendtag != null) return 'Zent it!';
    if (widget.request.recipientEmail != null) return 'Request emailed!';
    return 'Link created!';
  }

  String _subline() {
    if (widget.request.recipientZendtag != null) return '@${widget.request.recipientZendtag} will get a notification.';
    if (widget.request.recipientEmail != null) return 'Sent to ${widget.request.recipientEmail}';
    return 'Share the link or show the QR.';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final amount = widget.request.amount;
    final amountStr = amount == amount.roundToDouble() ? '\$${amount.toStringAsFixed(0)}' : '\$${amount.toStringAsFixed(2)}';

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
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 20),
          Text(_headline(), style: TextStyle(fontFamily: 'InstrumentSerif', fontStyle: FontStyle.italic, fontSize: 40, color: zt.textPrimary)),
          const SizedBox(height: 6),
          Text(amountStr, style: TextStyle(fontFamily: 'DMMono', fontSize: 16, color: zt.textSecondary)),
          const SizedBox(height: 4),
          Text(_subline(), textAlign: TextAlign.center, style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary)),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: PrimaryButton(label: 'Show QR', onPressed: widget.onShowQr)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlineActionButton(label: 'Done', onPressed: widget.onDone)),
        ],
      ),
    );
  }
}

// ── Shared field row widget ───────────────────────────────────────────────────

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: Text(label, style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
