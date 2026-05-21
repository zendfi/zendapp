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

// ── Entry point ───────────────────────────────────────────────────────────────

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

  // ── Open intent amount input ──
  final TextEditingController _amountController = TextEditingController();

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
    _amountController.dispose();
    super.dispose();
  }

  // ── Height fractions ──────────────────────────────────────────────────────

  double get _sheetHeightFraction {
    switch (_stage) {
      case QrPayStage.loading:
        return 0.45;
      case QrPayStage.confirm:
        // Open intent needs more space for the amount input
        if (intent.amountUsdc == null && intent.requestLinkId == null) {
          return 0.65;
        }
        return 0.60;
      case QrPayStage.pin:
        return 0.70;
      case QrPayStage.processing:
        return 0.45;
      case QrPayStage.success:
        return 0.50;
      case QrPayStage.error:
        return 0.55;
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
      final amount = _resolvedAmount ??
          double.tryParse(_amountController.text.replaceAll(',', '')) ??
          0.0;

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
          amountController: _amountController,
          onConfirm: () {
            // Fetch FX preview for open intent when user proceeds
            if (intent.amountUsdc == null && intent.requestLinkId == null) {
              final amount = double.tryParse(
                  _amountController.text.replaceAll(',', ''));
              if (amount != null && amount > 0) {
                _fetchFxPreview(amount);
              }
            }
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _stage = QrPayStage.pin;
            });
          },
        );

      case QrPayStage.pin:
        final amount = _resolvedAmount ??
            double.tryParse(_amountController.text.replaceAll(',', '')) ??
            0.0;
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
        final amount = _resolvedAmount ??
            double.tryParse(_amountController.text.replaceAll(',', '')) ??
            0.0;
        return SendProcessingStage(
          key: const ValueKey('processing'),
          amountFormatted: _formatAmount(amount),
          recipientZendtag: intent.zendtag,
        );

      case QrPayStage.success:
        final amount = _resolvedAmount ??
            double.tryParse(_amountController.text.replaceAll(',', '')) ??
            0.0;
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
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendColors.textSecondary,
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
    required this.amountController,
    required this.onConfirm,
  });

  final QrPaymentIntent intent;
  final double? resolvedAmount;
  final String? resolvedNote;
  final double? fxPreviewNgn;
  final TextEditingController amountController;
  final VoidCallback onConfirm;

  @override
  State<_QrConfirmStage> createState() => _QrConfirmStageState();
}

class _QrConfirmStageState extends State<_QrConfirmStage> {
  bool get _isOpenIntent =>
      widget.intent.amountUsdc == null && widget.intent.requestLinkId == null;

  double? get _effectiveAmount {
    if (widget.resolvedAmount != null) return widget.resolvedAmount;
    return double.tryParse(
        widget.amountController.text.replaceAll(',', ''));
  }

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

    final effectiveAmount = _effectiveAmount;
    final balanceUnknown = balanceLoading && balance == 0.0;
    final insufficientBalance = !balanceUnknown &&
        effectiveAmount != null &&
        effectiveAmount > balance;

    // Determine if the confirm button should be enabled
    bool canConfirm;
    if (_isOpenIntent) {
      canConfirm = effectiveAmount != null &&
          effectiveAmount > 0 &&
          !balanceUnknown &&
          !insufficientBalance;
    } else {
      canConfirm = !balanceUnknown && !insufficientBalance;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            'Pay @${widget.intent.zendtag}',
            style: const TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ZendColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Amount section
          if (_isOpenIntent) ...[
            // Open intent: amount text field
            TextField(
              controller: widget.amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontFamily: 'DMMono',
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: ZendColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: r'$0.00',
                hintStyle: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: ZendColors.textSecondary,
                ),
                filled: false,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ] else ...[
            // Fixed-amount intent: read-only amount display
            Text(
              _formatAmount(widget.resolvedAmount ?? 0),
              style: const TextStyle(
                fontFamily: 'InstrumentSerif',
                fontStyle: FontStyle.italic,
                fontSize: 40,
                color: ZendColors.textPrimary,
              ),
            ),
            // NGN equivalent
            if (widget.fxPreviewNgn != null) ...[
              const SizedBox(height: 4),
              Text(
                '≈ ₦${_formatNgn(widget.fxPreviewNgn!)}',
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 14,
                  color: ZendColors.textSecondary,
                ),
              ),
            ],
            // Note
            if (widget.resolvedNote != null &&
                widget.resolvedNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.resolvedNote!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: ZendColors.textSecondary,
                ),
              ),
            ],
          ],

          const SizedBox(height: 16),

          // Balance row
          Row(
            children: [
              const Text(
                'Balance: ',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: ZendColors.textSecondary,
                ),
              ),
              if (balanceUnknown)
                const ZendLoader(size: 14)
              else
                Text(
                  '\$${balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 13,
                    color: ZendColors.textSecondary,
                  ),
                ),
            ],
          ),

          // Insufficient balance error
          if (insufficientBalance) ...[
            const SizedBox(height: 6),
            const Text(
              'Insufficient balance',
              style: TextStyle(
                fontFamily: 'DMSans',
                fontSize: 13,
                color: ZendColors.destructive,
              ),
            ),
          ],

          const Spacer(),

          // Confirm button
          PrimaryButton(
            label: _isOpenIntent
                ? 'Zend'
                : 'Zend ${_formatAmount(widget.resolvedAmount ?? 0)}',
            onPressed: canConfirm ? widget.onConfirm : null,
          ),
        ],
      ),
    );
  }
}
