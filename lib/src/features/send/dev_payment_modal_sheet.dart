import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/dev_return_redirect_service.dart';
import '../../services/signing_policy_service.dart';
import '../../services/sound_service.dart';
import '../../services/wallet_session_cache.dart';
import 'send_shared_widgets.dart';

/// Stage machine for the "Pay with Zend" Payment Modal Sheet — the dedicated
/// native UI shown when a `zdfi.me` deep link resolves to a Developer-
/// created (`source='api'`) payment request (Requirement 4.1). Extends
/// [QrPaymentSheet]'s `loading → confirm → pin → processing → success/error`
/// pattern with two additional terminal stages for cases that don't apply
/// to peer-to-peer requests: `notFound` and `unavailable` (already
/// expired/paid/cancelled).
enum DevPayStage { loading, confirm, pin, processing, success, error, notFound, unavailable }

Future<void> showDevPaymentModalSheet(
  BuildContext context, {
  required String zendtag,
  required String requestLinkId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => DevPaymentModalSheet(zendtag: zendtag, requestLinkId: requestLinkId),
  );
}

class DevPaymentModalSheet extends StatefulWidget {
  const DevPaymentModalSheet({
    super.key,
    required this.zendtag,
    required this.requestLinkId,
  });

  final String zendtag;
  final String requestLinkId;

  @override
  State<DevPaymentModalSheet> createState() => _DevPaymentModalSheetState();
}

class _DevPaymentModalSheetState extends State<DevPaymentModalSheet>
    with SingleTickerProviderStateMixin {
  DevPayStage _stage = DevPayStage.loading;

  double? _amountUsdc;
  String? _description;
  String? _requesterDisplayName;
  String? _requesterZendtag;
  String? _errorMessage;
  String? _unavailableReason;

  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut));

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final model = ZendScope.of(context);
      final details = await model.walletService.apiClient
          .getPublicUserRequestData(widget.zendtag, widget.requestLinkId);

      if (!mounted) return;
      setState(() {
        _amountUsdc = details.amountUsdc;
        _description = details.description;
        _requesterDisplayName = details.requesterDisplayName;
        _requesterZendtag = details.requesterZendtag ?? widget.zendtag;
        _redirectUrl = details.redirectUrl;
        _stage = DevPayStage.confirm;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        // Distinguish "never existed" from "exists but terminal" via the
        // unfiltered status endpoint (Requirement 4.7 vs 4.4).
        await _resolveNotFoundOrUnavailable();
      } else {
        setState(() {
          _errorMessage = e.userMessage;
          _stage = DevPayStage.error;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load payment request. Check your connection.';
        _stage = DevPayStage.error;
      });
    }
  }

  Future<void> _resolveNotFoundOrUnavailable() async {
    try {
      final model = ZendScope.of(context);
      final status = await model.walletService.apiClient
          .getPublicRequestStatus(widget.zendtag, widget.requestLinkId, platform: _platform);
      if (!mounted) return;
      if (!status.found) {
        setState(() => _stage = DevPayStage.notFound);
        return;
      }
      setState(() {
        _unavailableReason = _describeStatus(status.status, status.expired);
        _stage = DevPayStage.unavailable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = DevPayStage.notFound);
    }
  }

  String _describeStatus(String? status, bool expired) {
    if (expired) return 'This payment request has expired.';
    switch (status) {
      case 'paid':
        return 'This payment request has already been paid.';
      case 'cancelled':
        return 'This payment request was cancelled.';
      default:
        return 'This payment request is no longer available.';
    }
  }

  String _formatAmount(double amount) =>
      amount == amount.roundToDouble() ? '\$${amount.toStringAsFixed(0)}' : '\$${amount.toStringAsFixed(2)}';

  /// Re-fetches the request's current status immediately before invoking
  /// the signing flow (Requirement 4.8). If it's no longer payable, aborts
  /// straight to the `unavailable` terminal state without ever touching
  /// the signing flow.
  Future<void> _onConfirmTap() async {
    final model = ZendScope.of(context);
    try {
      final status = await model.walletService.apiClient
          .getPublicRequestStatus(widget.zendtag, widget.requestLinkId, platform: _platform);
      if (!mounted) return;
      if (!status.found) {
        setState(() => _stage = DevPayStage.notFound);
        return;
      }
      if (!status.payable) {
        setState(() {
          _unavailableReason = _describeStatus(status.status, status.expired);
          _stage = DevPayStage.unavailable;
        });
        return;
      }
    } catch (_) {
      // Network failure on the race-check itself — fall through and let the
      // subsequent prepare/submit calls surface their own errors rather than
      // blocking the user on a transient connectivity blip here.
    }

    await _proceedToSign();
  }

  Future<void> _proceedToSign() async {
    final policy = SigningPolicyService();
    final cache = WalletSessionCache.instance;
    final amount = _amountUsdc ?? 0.0;
    final needsPin = await policy.requiresPinForAmount(amount);

    if (!mounted) return;
    if (!needsPin && cache.hasKeypair) {
      setState(() => _stage = DevPayStage.processing);
      await _executePayment(pin: null, keypairBytes: cache.keypair);
    } else {
      setState(() {
        _pinDigits = '';
        _pinError = null;
        _stage = DevPayStage.pin;
      });
    }
  }

  void _onPinKey(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      _pinError = null;
      if (value == 'del') {
        if (_pinDigits.isNotEmpty) _pinDigits = _pinDigits.substring(0, _pinDigits.length - 1);
        return;
      }
      if (_pinDigits.length >= 6) return;
      _pinDigits += value;
    });
    if (_pinDigits.length == 6) _submitPin();
  }

  Future<void> _submitPin() async {
    final pin = _pinDigits;
    setState(() => _stage = DevPayStage.processing);

    try {
      final model = ZendScope.of(context);
      final cache = WalletSessionCache.instance;

      if (cache.hasKeypair) {
        final valid = await model.signingPolicyService
            .verifyPinAgainstCache(pin, model.walletService);
        if (!valid) {
          if (!mounted) return;
          _handleWrongPin();
          return;
        }
        await _executePayment(pin: null, keypairBytes: cache.keypair);
      } else {
        await _executePayment(pin: pin, keypairBytes: null);
      }
    } on PinDecryptionException {
      if (!mounted) return;
      _handleWrongPin();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Cancelling or failing at the signing layer must never mark the
      // request failed/expired (Requirement 4.9) — we simply return to
      // `confirm` so the user can retry, rather than showing a hard error
      // for what may just be a mis-typed PIN surfaced as a generic API
      // exception from a lower layer.
      setState(() {
        _errorMessage = e.userMessage;
        _stage = DevPayStage.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = DevPayStage.error;
      });
    }
  }

  void _handleWrongPin() {
    _pinAttempts++;
    if (_pinAttempts >= 5) {
      final model = ZendScope.of(context);
      model.appLockService.lock();
      setState(() {
        _errorMessage = 'Too many incorrect PIN attempts. Please unlock again.';
        _stage = DevPayStage.error;
      });
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _stage = DevPayStage.pin;
      });
    }
  }

  Future<void> _executePayment({String? pin, dynamic keypairBytes}) async {
    try {
      final model = ZendScope.of(context);

      final prepared = await model.walletService.apiClient
          .prepareDevRequestPayment(widget.zendtag, widget.requestLinkId);

      final amount = prepared.amountUsdc ?? _amountUsdc ?? 0.0;

      final String partiallySignedTxB64;
      if (keypairBytes != null) {
        partiallySignedTxB64 = await model.walletService.buildAndSignTransactionFromCache(
          keypairBytes: keypairBytes,
          amountUsdc: amount,
          recipientAddress: prepared.recipientWalletAddress,
          blockhash: prepared.blockhash,
          feePayerAddress: prepared.feePayer,
          senderAtaOverride: prepared.senderAta,
          recipientAtaOverride: prepared.recipientAta,
        );
      } else {
        partiallySignedTxB64 = await model.walletService.buildAndSignTransaction(
          pin: pin!,
          amountUsdc: amount,
          recipientAddress: prepared.recipientWalletAddress,
          blockhash: prepared.blockhash,
          feePayerAddress: prepared.feePayer,
          senderAtaOverride: prepared.senderAta,
          recipientAtaOverride: prepared.recipientAta,
        );
      }

      final result = await model.walletService.apiClient.submitDevRequestPayment(
        widget.zendtag,
        widget.requestLinkId,
        partiallySignedTxB64,
        platform: _platform,
      );

      if (!mounted) return;

      unawaited(model.fetchBalance());

      setState(() => _stage = DevPayStage.success);
      HapticFeedback.mediumImpact();
      unawaited(SoundService.playZentSuccess());

      // Fire-and-forget the return redirect — never blocks the success UI.
      if (result.returnToken != null) {
        unawaited(_performReturnRedirect(result.returnToken!));
      }
    } on PinDecryptionException {
      rethrow;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.userMessage;
        _stage = DevPayStage.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _stage = DevPayStage.error;
      });
    }
  }

  bool _redirectFailed = false;
  String? _redirectUrl;

  /// Performs the post-confirmation return redirect using the
  /// Developer-configured `redirect_url` captured at `_load()` time
  /// (Requirement 5.3). A non-null [token] implies the backend determined
  /// this request qualifies (source='api' + non-empty redirect_url), so
  /// `_redirectUrl` should be present here; if it's somehow absent, we
  /// simply skip the redirect rather than attempting one with no
  /// destination.
  Future<void> _performReturnRedirect(String token) async {
    if (_redirectUrl == null) return;
    final model = ZendScope.of(context);

    final success = await DevReturnRedirectService.redirectAndReportOutcome(
      apiClient: model.walletService.apiClient,
      requestId: widget.requestLinkId,
      redirectUrl: _redirectUrl!,
      token: token,
      platform: _platform,
    );

    if (!mounted) return;
    if (!success) {
      setState(() => _redirectFailed = true);
    }
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenHeight = mq.size.height;

    return PopScope(
      canPop: _stage != DevPayStage.processing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: screenHeight * 0.92,
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
                  duration: const Duration(milliseconds: 180),
                  reverseDuration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation);
                    return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
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
      case DevPayStage.loading:
        return const Center(
          key: ValueKey('loading'),
          child: ZendLoader(size: 32),
        );

      case DevPayStage.confirm:
        return _DevConfirmStage(
          key: const ValueKey('confirm'),
          amountUsdc: _amountUsdc ?? 0.0,
          description: _description,
          requesterDisplayName: _requesterDisplayName,
          requesterZendtag: _requesterZendtag ?? widget.zendtag,
          onConfirm: _onConfirmTap,
        );

      case DevPayStage.pin:
        return SendPinStage(
          key: const ValueKey('pin'),
          amountFormatted: _formatAmount(_amountUsdc ?? 0.0),
          recipientZendtag: _requesterZendtag ?? widget.zendtag,
          note: _description ?? '',
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = DevPayStage.confirm;
          }),
        );

      case DevPayStage.processing:
        return SendProcessingStage(
          key: const ValueKey('processing'),
          amountFormatted: _formatAmount(_amountUsdc ?? 0.0),
          recipientZendtag: _requesterZendtag ?? widget.zendtag,
        );

      case DevPayStage.success:
        return Column(
          key: const ValueKey('success'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: SendSuccessStage(
                amountFormattedExact: '\$${(_amountUsdc ?? 0.0).toStringAsFixed(2)}',
                recipientZendtag: _requesterZendtag ?? widget.zendtag,
                onDone: _dismiss,
              ),
            ),
            if (_redirectFailed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ZendColors.destructive.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Payment confirmed — return to ${_requesterDisplayName ?? 'the developer'}'s site failed.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.destructive),
                  ),
                ),
              ),
          ],
        );

      case DevPayStage.error:
        return SendErrorStage(
          key: const ValueKey('error'),
          errorMessage: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            setState(() {
              _pinDigits = '';
              _pinError = null;
              _errorMessage = null;
              _stage = DevPayStage.confirm;
            });
          },
          onCancel: _dismiss,
        );

      case DevPayStage.notFound:
        return _DevTerminalStage(
          key: const ValueKey('notFound'),
          title: 'Not found',
          message: 'This payment request could not be found.',
          onDismiss: _dismiss,
        );

      case DevPayStage.unavailable:
        return _DevTerminalStage(
          key: const ValueKey('unavailable'),
          title: 'Unavailable',
          message: _unavailableReason ?? 'This payment request is no longer available.',
          onDismiss: _dismiss,
        );
    }
  }
}

class _DevConfirmStage extends StatelessWidget {
  const _DevConfirmStage({
    super.key,
    required this.amountUsdc,
    required this.description,
    required this.requesterDisplayName,
    required this.requesterZendtag,
    required this.onConfirm,
  });

  final double amountUsdc;
  final String? description;
  final String? requesterDisplayName;
  final String requesterZendtag;
  final VoidCallback onConfirm;

  String _formatAmount(double amount) =>
      amount == amount.roundToDouble() ? '\$${amount.toStringAsFixed(0)}' : '\$${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    final model = ZendScope.of(context);
    final balance = model.balance;
    final insufficientBalance = amountUsdc > balance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            requesterDisplayName?.isNotEmpty == true
                ? 'Pay $requesterDisplayName'
                : 'Pay @$requesterZendtag',
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: zt.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '@$requesterZendtag',
            style: TextStyle(fontFamily: 'DMMono', fontSize: 13, color: zt.textSecondary),
          ),
          const SizedBox(height: 20),
          Text(
            _formatAmount(amountUsdc),
            style: TextStyle(
              fontFamily: 'InstrumentSerif',
              fontStyle: FontStyle.italic,
              fontSize: 40,
              color: zt.textPrimary,
            ),
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
            ),
          ],
          if (insufficientBalance) ...[
            const SizedBox(height: 8),
            const Text(
              'Insufficient balance',
              style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: ZendColors.destructive),
            ),
          ],
          const Spacer(),
          PrimaryButton(
            label: 'Zend ${_formatAmount(amountUsdc)}',
            onPressed: insufficientBalance ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}

class _DevTerminalStage extends StatelessWidget {
  const _DevTerminalStage({
    super.key,
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 28, color: zt.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(label: 'Close', onPressed: onDismiss),
            ),
          ],
        ),
      ),
    );
  }
}
