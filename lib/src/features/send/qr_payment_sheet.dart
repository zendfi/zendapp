import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../models/qr_payment_intent.dart';
import '../../services/sound_service.dart';
import 'send_shared_widgets.dart';

// ── Stage enum ────────────────────────────────────────────────────────────────

enum QrPayStage { loading, confirm, pin, processing, success, error }

// ── Entry points ──────────────────────────────────────────────────────────────

Future<void> showQrPaymentSheet(
  BuildContext context, {
  required QrPaymentIntent intent,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => QrPaymentSheet(intent: intent),
  );
}

/// Variant that accepts a [NavigatorState] instead of a [BuildContext].
/// Use this when calling from an async gap (e.g. after Future.delayed) to
/// avoid the use_build_context_synchronously lint warning.
Future<void> showQrPaymentSheetFromNavigator(
  NavigatorState navigator, {
  required QrPaymentIntent intent,
}) {
  return showModalBottomSheet(
    context: navigator.context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => QrPaymentSheet(intent: intent),
  );
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class QrPaymentSheet extends StatefulWidget {
  const QrPaymentSheet({super.key, required this.intent});

  final QrPaymentIntent intent;

  @override
  State<QrPaymentSheet> createState() => _QrPaymentSheetState();
}

class _QrPaymentSheetState extends State<QrPaymentSheet>
    with SingleTickerProviderStateMixin {
  static const Duration _stageTransition = Duration(milliseconds: 180);
  static const Duration _sheetResize = Duration(milliseconds: 220);

  // ── Stage ──
  QrPayStage _stage = QrPayStage.loading;

  // ── Resolved payment data ──
  double? _resolvedAmount;
  String? _resolvedNote;

  // ── Error ──
  String? _errorMessage;

  // ── PIN ──
  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  // ── Shake animation ──
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  // ── FX preview ──
  double? _fxPreviewNgn;

  // ── Open intent amount input (keypad-driven, no device keyboard) ──
  String _digits = '';

  // ── Whether the error was a fetch error (vs transfer error) ──
  bool _isFetchError = false;

  QrPaymentIntent get intent => widget.intent;

  @override
  void initState() {
    super.initState();

    // Set up shake animation (same TweenSequence as SendFlowSheet)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticOut,
    ));

    if (intent.requestLinkId != null) {
      // Request link intent — start in loading, fetch details
      _stage = QrPayStage.loading;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchRequestLink());
    } else if (intent.amountUsdc != null) {
      // Fixed-amount intent — go straight to confirm
      _resolvedAmount = intent.amountUsdc;
      _resolvedNote = intent.note;
      _stage = QrPayStage.confirm;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fetchFxPreview(_resolvedAmount!));
    } else {
      // Open intent — user enters amount
      _stage = QrPayStage.confirm;
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  // ── Height fractions ──────────────────────────────────────────────────────

  double get _sheetHeightFraction {
    switch (_stage) {
      case QrPayStage.loading:
        return 0.92;
      case QrPayStage.confirm:
        return 0.92;
      case QrPayStage.pin:
        return 0.92;
      case QrPayStage.processing:
        return 0.92;
      case QrPayStage.success:
        return 0.92;
      case QrPayStage.error:
        return 0.92;
    }
  }

  // ── Amount formatting helpers ─────────────────────────────────────────────

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  String _formatAmountExact(double amount) =>
      '\$${amount.toStringAsFixed(2)}';

  // ── Fetch request link ────────────────────────────────────────────────────

  Future<void> _fetchRequestLink() async {
    try {
      final model = ZendScope.of(context);
      final details = await model.walletService.apiClient
          .getPublicUserRequestData(intent.zendtag, intent.requestLinkId!);
      if (!mounted) return;
      setState(() {
        _resolvedAmount = details.amountUsdc;
        _resolvedNote = details.description;
        _stage = QrPayStage.confirm;
        _isFetchError = false;
      });
      _fetchFxPreview(_resolvedAmount!);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.statusCode == 404
            ? 'This payment request is no longer available'
            : e.userMessage;
        _stage = QrPayStage.error;
        _isFetchError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load payment request. Check your connection.';
        _stage = QrPayStage.error;
        _isFetchError = true;
      });
    }
  }

  // ── FX preview ────────────────────────────────────────────────────────────

  Future<void> _fetchFxPreview(double amount) async {
    try {
      final model = ZendScope.of(context);
      final preview = await model.fxService.getPreview(amount);
      if (!mounted) return;
      setState(() => _fxPreviewNgn = preview.amountNgn);
    } catch (_) {
      // FX preview is optional — silently ignore failures
    }
  }

  // ── Keypad handler (open intent) ─────────────────────────────────────────

  void _onAmountKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (value == '.') {
        if (!_digits.contains('.')) {
          _digits = _digits.isEmpty ? '0.' : '$_digits.';
        }
      } else if (RegExp(r'[0-9]').hasMatch(value)) {
        // Max 2 decimal places
        if (_digits.contains('.')) {
          final parts = _digits.split('.');
          if (parts.length == 2 && parts[1].length >= 2) return;
        }
        // No leading zeros
        if (_digits == '0') {
          if (value == '0') return;
          _digits = value;
        } else {
          _digits += value;
        }
      }
    });
  }

  double get _parsedAmount =>
      _digits.isEmpty ? 0 : (double.tryParse(_digits) ?? 0);

  // ── PIN key handler ───────────────────────────────────────────────────────

  void _onPinKey(String value) {
    HapticFeedback.lightImpact();

    setState(() {
      _pinError = null;

      if (value == 'del') {
        if (_pinDigits.isNotEmpty) {
          _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        }
        return;
      }

      if (_pinDigits.length >= 4) return;
      _pinDigits += value;
    });

    if (_pinDigits.length == 4) {
      _submitPin();
    }
  }

  // ── Submit PIN / execute transfer ─────────────────────────────────────────

  Future<void> _submitPin() async {
    final pin = _pinDigits;
    setState(() => _stage = QrPayStage.processing);

    try {
      final model = ZendScope.of(context);
      final amount = _resolvedAmount ?? _parsedAmount;

      await model.transferService.sendTransfer(
        recipientZendtag: intent.zendtag,
        amountUsdc: amount,
        pin: pin,
        note: _resolvedNote,
      );

      if (!mounted) return;

      await model.recordTransfer(
        recipientZendtag: intent.zendtag,
        recipientDisplayName: '@${intent.zendtag}',
        amount: amount,
        note: _resolvedNote,
      );

      unawaited(model.fetchBalance());
      unawaited(model.fetchHistory());

      setState(() => _stage = QrPayStage.success);
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());
    } on PinDecryptionException {
      if (!mounted) return;
      _pinAttempts++;
      if (_pinAttempts >= 5) {
        setState(() {
          _errorMessage = 'Too many incorrect PIN attempts.';
          _stage = QrPayStage.error;
          _isFetchError = false;
        });
      } else {
        _shakeController.forward(from: 0);
        setState(() {
          _pinDigits = '';
          _pinError = 'Incorrect PIN';
          _stage = QrPayStage.pin;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = QrPayStage.error;
        _isFetchError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = QrPayStage.error;
        _isFetchError = false;
      });
    }
  }

  void _dismiss() => Navigator.of(context).pop();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != QrPayStage.processing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: AnimatedContainer(
          duration: _sheetResize,
          curve: Curves.easeOutCubic,
          height: screenHeight * _sheetHeightFraction,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZendRadii.xxl),
            ),
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
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: RepaintBoundary(child: _buildStageContent()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_stage) {
      case QrPayStage.loading:
        return _QrLoadingStage(
          key: const ValueKey('loading'),
          zendtag: intent.zendtag,
        );

      case QrPayStage.confirm:
        return _QrConfirmStage(
          key: const ValueKey('confirm'),
          intent: intent,
          resolvedAmount: _resolvedAmount,
          resolvedNote: _resolvedNote,
          fxPreviewNgn: _fxPreviewNgn,
          digits: _digits,
          onAmountKey: _onAmountKey,
          onConfirm: () {
            // Fetch FX preview for open intent when user proceeds
            if (intent.amountUsdc == null && intent.requestLinkId == null) {
              if (_parsedAmount > 0) _fetchFxPreview(_parsedAmount);
            }
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = QrPayStage.pin;
            });
          },
        );

      case QrPayStage.pin:
        final amount = _resolvedAmount ?? _parsedAmount;
        return SendPinStage(
          key: const ValueKey('pin'),
          amountFormatted: _formatAmount(amount),
          recipientZendtag: intent.zendtag,
          note: _resolvedNote ?? '',
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = QrPayStage.confirm;
            });
          },
        );

      case QrPayStage.processing:
        final amount = _resolvedAmount ?? _parsedAmount;
        return SendProcessingStage(
          key: const ValueKey('processing'),
          amountFormatted: _formatAmount(amount),
          recipientZendtag: intent.zendtag,
        );

      case QrPayStage.success:
        final amount = _resolvedAmount ?? _parsedAmount;
        return SendSuccessStage(
          key: const ValueKey('success'),
          amountFormattedExact: _formatAmountExact(amount),
          recipientZendtag: intent.zendtag,
          onDone: _dismiss,
        );

      case QrPayStage.error:
        return SendErrorStage(
          key: const ValueKey('error'),
          errorMessage: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            if (_isFetchError) {
              // Re-fetch the request link
              setState(() {
                _stage = QrPayStage.loading;
                _errorMessage = null;
              });
              _fetchRequestLink();
            } else {
              // Re-enter PIN stage for transfer errors
              setState(() {
                _pinDigits = '';
                _pinError = null;
                _stage = QrPayStage.pin;
              });
            }
          },
          onCancel: _dismiss,
        );
    }
  }
}

// ── Loading stage ─────────────────────────────────────────────────────────────

class _QrLoadingStage extends StatelessWidget {
  const _QrLoadingStage({super.key, required this.zendtag});

  final String zendtag;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendLoader(size: 32),
          const SizedBox(height: 20),
          Text(
            'Loading payment request...',
            style: TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendTheme.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirm stage ─────────────────────────────────────────────────────────────

class _QrConfirmStage extends StatefulWidget {
  const _QrConfirmStage({
    super.key,
    required this.intent,
    required this.resolvedAmount,
    required this.resolvedNote,
    required this.fxPreviewNgn,
    required this.digits,
    required this.onAmountKey,
    required this.onConfirm,
  });

  final QrPaymentIntent intent;
  final double? resolvedAmount;
  final String? resolvedNote;
  final double? fxPreviewNgn;
  // Open intent: keypad-driven digit string
  final String digits;
  final ValueChanged<String> onAmountKey;
  final VoidCallback onConfirm;

  @override
  State<_QrConfirmStage> createState() => _QrConfirmStageState();
}

class _QrConfirmStageState extends State<_QrConfirmStage> {
  bool get _isOpenIntent =>
      widget.intent.amountUsdc == null && widget.intent.requestLinkId == null;

  double get _parsedAmount =>
      widget.digits.isEmpty ? 0 : (double.tryParse(widget.digits) ?? 0);

  double? get _effectiveAmount =>
      widget.resolvedAmount ?? (_parsedAmount > 0 ? _parsedAmount : null);

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '\$${amount.toStringAsFixed(0)}';
    }
    return '\$${amount.toStringAsFixed(2)}';
  }

  String _formatNgn(double value) {
    final rounded = value.round();
    final text = rounded.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final indexFromEnd = text.length - i;
      buffer.write(text[i]);
      if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final model = ZendScope.of(context);
    final balance = model.balance;
    final balanceLoading = model.balanceLoading;
    final compact = MediaQuery.of(context).size.height < 760;

    final effectiveAmount = _effectiveAmount;
    final balanceUnknown = balanceLoading && balance == 0.0;
    final insufficientBalance = !balanceUnknown &&
        effectiveAmount != null &&
        effectiveAmount > balance;

    bool canConfirm;
    if (_isOpenIntent) {
      canConfirm = _parsedAmount > 0 && !balanceUnknown && !insufficientBalance;
    } else {
      canConfirm = !balanceUnknown && !insufficientBalance;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Recipient + balance row ──────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pay @${widget.intent.zendtag}',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ZendTheme.of(context).textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (balanceUnknown)
                    const ZendLoader(size: 12)
                  else
                    Text(
                      '\$${balance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontFamily: 'DMMono',
                        fontSize: 12,
                        color: ZendTheme.of(context).textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Amount display ───────────────────────────────────────────────
          if (_isOpenIntent) ...[
            // Keypad-driven amount — mirrors SendScreen's _UsdAmountDisplay
            _AmountDisplay(digits: widget.digits, compact: compact),
            const SizedBox(height: 4),
            // NGN equivalent placeholder (shown once FX is fetched after confirm)
            if (insufficientBalance)
              Text(
                'Insufficient balance',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                ),
              ),
          ] else ...[
            // Fixed / request amount — read-only
            Text(
              _formatAmount(widget.resolvedAmount ?? 0),
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: ZendTheme.of(context).textPrimary,
              ),
            ),
            if (widget.fxPreviewNgn != null) ...[
              const SizedBox(height: 4),
              Text(
                '≈ ₦${_formatNgn(widget.fxPreviewNgn!)}',
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 14,
                  color: ZendTheme.of(context).textSecondary,
                ),
              ),
            ],
            if (widget.resolvedNote != null &&
                widget.resolvedNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.resolvedNote!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: ZendTheme.of(context).textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (insufficientBalance)
              Text(
                'Insufficient balance',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.destructive,
                ),
              ),
          ],

          // ── Keypad (open intent only) ────────────────────────────────────
          if (_isOpenIntent) ...[
            const Spacer(),
            _AmountKeypad(
              onTap: widget.onAmountKey,
              keyHeight: compact ? 52 : 64,
            ),
            const SizedBox(height: 10),
          ] else ...[
            const Spacer(),
          ],

          // ── Confirm button ───────────────────────────────────────────────
          PrimaryButton(
            label: _isOpenIntent
                ? (_parsedAmount > 0
                    ? 'Zend ${_formatAmount(_parsedAmount)}'
                    : 'Enter amount')
                : 'Zend ${_formatAmount(widget.resolvedAmount ?? 0)}',
            onPressed: canConfirm ? widget.onConfirm : null,
          ),
        ],
      ),
    );
  }
}

// ── Amount display (mirrors SendScreen's split rendering) ─────────────────────

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.digits, required this.compact});

  final String digits;
  final bool compact;

  String get _wholePart {
    if (digits.isEmpty) return '0';
    if (digits.contains('.')) return digits.split('.')[0];
    return digits;
  }

  String? get _decimalPart {
    if (!digits.contains('.')) return null;
    final parts = digits.split('.');
    return parts.length > 1 ? parts[1] : '';
  }

  bool get _hasDecimal => digits.contains('.');

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final wholeSize = compact ? 64.0 : 76.0;
    final decSize = compact ? 26.0 : 30.0;

    final wholeStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textPrimary,
      fontSize: wholeSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );
    final decStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textPrimary.withValues(alpha: 0.8),
      fontSize: decSize,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );
    final currencyStyle = TextStyle(
      fontFamily: 'InstrumentSerif',
      color: zt.textPrimary.withValues(alpha: 0.5),
      fontSize: wholeSize * 0.5,
      fontStyle: FontStyle.italic,
      height: 1.0,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: wholeSize * 0.08),
          child: Text('\$', style: currencyStyle),
        ),
        Text(_wholePart, style: wholeStyle),
        if (_hasDecimal) ...[
          const SizedBox(width: 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('.', style: decStyle),
                  Text(
                    _decimalPart == null || _decimalPart!.isEmpty
                        ? '—'
                        : _decimalPart!,
                    style: decStyle,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Amount keypad ─────────────────────────────────────────────────────────────

class _AmountKeypad extends StatelessWidget {
  const _AmountKeypad({required this.onTap, required this.keyHeight});

  final ValueChanged<String> onTap;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', 'del',
    ];

    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: col == 2 ? 0 : 10,
                      bottom: row == 3 ? 0 : 10,
                    ),
                    child: _AmountKey(
                      label: keys[row * 3 + col],
                      keyHeight: keyHeight,
                      onTap: () => onTap(keys[row * 3 + col]),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _AmountKey extends StatefulWidget {
  const _AmountKey({
    required this.label,
    required this.onTap,
    required this.keyHeight,
  });

  final String label;
  final VoidCallback onTap;
  final double keyHeight;

  @override
  State<_AmountKey> createState() => _AmountKeyState();
}

class _AmountKeyState extends State<_AmountKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final isDel = widget.label == 'del';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: ZendMotion.keypadPress,
        curve: Curves.easeOut,
        scale: _pressed ? 0.94 : 1,
        child: SizedBox(
          height: widget.keyHeight,
          child: Center(
            child: isDel
                ? ZendBackspaceIcon(color: zt.textPrimary, size: 24)
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 24,
                      color: zt.textPrimary,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
