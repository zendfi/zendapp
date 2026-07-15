import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
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
  static const int _descriptionMaxLength = 140;

  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _recipientController;

  double _amount = 0;
  DateTime? _expiryDate;
  String? _expiryError;

  // Recipient resolution state
  String? _resolvedZendtag;       // confirmed zendtag (without @)
  String? _resolvedDisplayName;   // display name for confirmed zendtag
  String? _recipientEmail;        // confirmed email address
  String? _recipientError;        // inline error on the field
  bool _resolvingZendtag = false;
  Timer? _resolveDebounce;

  @override
  void initState() {
    super.initState();
    _amount = widget.initialAmount ?? 0;
    _amountController = TextEditingController(
      text: _amount > 0 ? _amount.toString() : '',
    );
    _descriptionController = TextEditingController();
    _recipientController = TextEditingController();
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _amountController.dispose();
    _descriptionController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  bool get _canCreate => _amount > 0;

  bool get _hasValidRecipient => _resolvedZendtag != null || _recipientEmail != null;

  // ── Stage ──
  // null = form, true = loading, false = success
  bool? _stage; // null=form, true=loading, false=success
  PaymentRequest? _createdRequest;

  String get _titleText {
    if (_amount > 0) {
      return 'Create payment request for ${formatRequestAmount(_amount)}';
    }
    return 'Create payment request';
  }

  String get _buttonLabel {
    if (!_hasValidRecipient) return 'Create link';
    if (_resolvedZendtag != null) return 'Send to @$_resolvedZendtag';
    return 'Send to $_recipientEmail';
  }

  void _onAmountChanged(String value) {
    final parsed = validateAmountInput(value);
    setState(() {
      _amount = parsed ?? 0;
    });
  }

  void _onRecipientChanged(String value) {
    _resolveDebounce?.cancel();
    final trimmed = value.trim();

    // Clear previous resolution
    setState(() {
      _resolvedZendtag = null;
      _resolvedDisplayName = null;
      _recipientEmail = null;
      _recipientError = null;
      _resolvingZendtag = false;
    });

    if (trimmed.isEmpty) return;

    if (trimmed.startsWith('@')) {
      // Zendtag path — debounce 500ms then resolve
      final tag = trimmed.substring(1).toLowerCase();
      if (tag.isEmpty) return;
      _resolveDebounce = Timer(const Duration(milliseconds: 500), () {
        _resolveZendtag(tag);
      });
    } else if (trimmed.contains('@')) {
      // Email path — basic format check, no backend call needed at this stage
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (emailRegex.hasMatch(trimmed)) {
        setState(() => _recipientEmail = trimmed);
      }
      // If format is invalid, treat as empty (no error shown while typing)
    }
    // Otherwise: not a zendtag or email — treat as empty
  }

  Future<void> _resolveZendtag(String tag) async {
    if (!mounted) return;
    final model = ZendScope.of(context);

    // Don't allow self-requests
    if (tag == model.currentZendtag) {
      setState(() {
        _recipientError = "You can't request from yourself.";
        _resolvingZendtag = false;
      });
      return;
    }

    setState(() => _resolvingZendtag = true);

    try {
      final resolved = await model.zendtagService.resolve(tag);
      if (!mounted) return;

      // Check again after async gap
      if (resolved.zendtag == model.currentZendtag) {
        setState(() {
          _recipientError = "You can't request from yourself.";
          _resolvingZendtag = false;
        });
        return;
      }

      setState(() {
        _resolvedZendtag = resolved.zendtag;
        _resolvedDisplayName = resolved.displayName;
        _recipientError = null;
        _resolvingZendtag = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Zendtag not found — treat as empty (no error, per spec)
      setState(() {
        _resolvedZendtag = null;
        _resolvedDisplayName = null;
        _resolvingZendtag = false;
      });
    }
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null) {
      if (!isValidExpiryDate(picked)) {
        setState(() {
          _expiryError = 'Please select a future date';
        });
      } else {
        setState(() {
          _expiryDate = picked;
          _expiryError = null;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _onCreateLink() {
    if (!_canCreate || _stage == true) return;

    final model = ZendScope.of(context);
    final resolvedZendtag = _resolvedZendtag;
    final recipientEmail = _recipientEmail;

    setState(() => _stage = true); // loading

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      PaymentRequest request;
      try {
        final response = await model.walletService.apiClient.createPaymentRequest(
          amountUsdc: _amount > 0 ? _amount : null,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          expiresAt: _expiryDate,
          recipientZendtag: resolvedZendtag,
          recipientEmail: recipientEmail,
        );

        request = PaymentRequest(
          id: response['id'] as String,
          link: response['link_url'] as String,
          amount: (response['amount_usdc'] as num?)?.toDouble() ?? _amount,
          description: _descriptionController.text.trim(),
          createdAt: DateTime.now(),
          expiryDate: _expiryDate,
          status: PaymentRequestStatus.pending,
          recipientZendtag: response['recipient_zendtag'] as String? ?? resolvedZendtag,
          recipientEmail: response['recipient_email'] as String? ?? recipientEmail,
        );
      } catch (_) {
        final requestId = generateRequestId();
        final link = buildRequestLink(model.username, requestId);
        request = PaymentRequest(
          id: requestId,
          link: link,
          amount: _amount,
          description: _descriptionController.text.trim(),
          createdAt: DateTime.now(),
          expiryDate: _expiryDate,
          status: PaymentRequestStatus.pending,
          recipientZendtag: resolvedZendtag,
          recipientEmail: recipientEmail,
        );
      }

      model.addPaymentRequest(request);

      if (mounted) {
        HapticFeedback.mediumImpact();
        unawaited(SoundService.playZentSuccess());
        setState(() {
          _stage = false; // success
          _createdRequest = request;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final descRemaining = remainingCharacters(
      _descriptionController.text,
      _descriptionMaxLength,
    );

    // ── Loading stage ──────────────────────────────────────────────────────
    if (_stage == true) {
      final zt = ZendTheme.of(context);
      return Container(
        decoration: BoxDecoration(
          color: zt.bgPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
        ),
        child: SizedBox(
          height: 280,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ZendLoader(size: 32),
                const SizedBox(height: 20),
                Text(
                  'Creating request…',
                  style: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Success stage ──────────────────────────────────────────────────────
    if (_stage == false && _createdRequest != null) {
      return _RequestSuccessStage(
        request: _createdRequest!,
        onDone: () => Navigator.of(context).pop(),
        onShowQr: () => showRequestQrSheet(context, request: _createdRequest!),
      );
    }

    // ── Form stage ─────────────────────────────────────────────────────────
    final zt = ZendTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ZendRadii.xxl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ZendScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ZendSheetHandle(),
              const SizedBox(height: ZendSpacing.lg),

              Text(
                _titleText,
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xl),

              if (widget.amountReadOnly) ...[
                Text(
                  formatRequestAmount(_amount),
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    color: zt.textPrimary,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: _onAmountChanged,
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: zt.textPrimary,
                  ),
                  decoration: InputDecoration(
                    prefixText: r'$ ',
                    prefixStyle: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: zt.textSecondary,
                    ),
                    hintText: '0.00',
                    hintStyle: TextStyle(
                      fontFamily: 'DMMono',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: zt.textSecondary,
                    ),
                    filled: true,
                    fillColor: zt.bgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZendRadii.md),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ZendSpacing.md,
                      vertical: ZendSpacing.sm,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: ZendSpacing.lg),

              TextField(
                controller: _descriptionController,
                maxLines: 2,
                minLines: 1,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_descriptionMaxLength),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Description (optional)',
                  hintStyle: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textSecondary,
                  ),
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: ZendSpacing.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$descRemaining remaining',
                  style: TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: descRemaining < 20
                        ? ZendColors.destructive
                        : zt.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: ZendSpacing.md),

              TextField(
                controller: _recipientController,
                onChanged: _onRecipientChanged,
                decoration: InputDecoration(
                  hintText: '@zendtag or email address',
                  hintStyle: TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 15,
                    color: zt.textSecondary,
                  ),
                  prefixIcon: Icon(
                    Icons.person_outline,
                    size: 20,
                    color: zt.textSecondary,
                  ),
                  suffixIcon: _resolvingZendtag
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: ZendLoader(size: 16, strokeWidth: 2, color: zt.textSecondary),
                        )
                      : _resolvedZendtag != null
                          ? Icon(Icons.check_circle, size: 20, color: zt.positive)
                          : _recipientEmail != null
                              ? Icon(Icons.check_circle, size: 20, color: zt.positive)
                              : null,
                  filled: true,
                  fillColor: zt.bgSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZendRadii.md),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZendSpacing.md,
                    vertical: ZendSpacing.sm,
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: zt.textPrimary,
                ),
              ),
              if (_resolvedDisplayName != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '$_resolvedDisplayName (@$_resolvedZendtag)',
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: zt.positive,
                    ),
                  ),
                ),
              ],
              if (_recipientError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _recipientError!,
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 12,
                      color: ZendColors.destructive,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: ZendSpacing.md),

              _TappableRow(
                label: _expiryDate != null
                    ? 'Expires ${_formatDate(_expiryDate!)}'
                    : 'Set expiry date',
                trailing: Icon(Icons.chevron_right, size: 18, color: zt.textSecondary),
                onTap: _pickExpiryDate,
              ),
              if (_expiryError != null) ...[
                const SizedBox(height: ZendSpacing.xxs),
                Text(
                  _expiryError!,
                  style: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
              ],

              const SizedBox(height: ZendSpacing.xxl),
              const Spacer(),

              PrimaryButton(
                label: _buttonLabel,
                onPressed: _canCreate ? _onCreateLink : () {},
                backgroundColor: _canCreate ? zt.accent : zt.bgSecondary,
                foregroundColor: _canCreate ? ZendColors.textOnDeep : zt.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableRow extends StatelessWidget {
  const _TappableRow({
    required this.label,
    required this.trailing,
    required this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(ZendRadii.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ZendSpacing.md,
          vertical: ZendSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: zt.bgSecondary,
          borderRadius: BorderRadius.circular(ZendRadii.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 15,
                  color: zt.textPrimary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

// ── Request success stage ─────────────────────────────────────────────────────

class _RequestSuccessStage extends StatefulWidget {
  const _RequestSuccessStage({
    required this.request,
    required this.onDone,
    required this.onShowQr,
  });

  final PaymentRequest request;
  final VoidCallback onDone;
  final VoidCallback onShowQr;

  @override
  State<_RequestSuccessStage> createState() => _RequestSuccessStageState();
}

class _RequestSuccessStageState extends State<_RequestSuccessStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  String _headline() {
    if (widget.request.recipientZendtag != null) {
      return 'Zent It!';
    }
    if (widget.request.recipientEmail != null) {
      return 'Request emailed!';
    }
    return 'Link created!';
  }

  String _subline() {
    if (widget.request.recipientZendtag != null) {
      return '@${widget.request.recipientZendtag} will get a notification.';
    }
    if (widget.request.recipientEmail != null) {
      return 'Sent to ${widget.request.recipientEmail}';
    }
    return 'Share the link or show the QR.';
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: zt.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZendSheetHandle(),
            const SizedBox(height: 32),
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: ZendColors.positive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _headline(),
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: zt.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatAmount(widget.request.amount),
              style: TextStyle(
                fontFamily: 'DMMono',
                fontSize: 16,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _subline(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: zt.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Show QR',
                onPressed: widget.onShowQr,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(
                label: 'Done',
                onPressed: widget.onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
