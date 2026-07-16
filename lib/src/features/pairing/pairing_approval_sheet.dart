import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/wallet_session_cache.dart';
import '../send/send_shared_widgets.dart';
import 'package:solar_icons/solar_icons.dart';

/// Stage machine for the "Pay with Zend" CLI device-pairing approval
/// screen. Reuses the exact same PIN-entry widget, shake animation, and
/// session-signing decision pattern as [QrPaymentSheet]
/// (`_proceedFromConfirm` → `SigningPolicyService`/`WalletSessionCache`) —
/// no bespoke dialog, no new signing UI, so the pairing flow feels and
/// behaves identically to every other confirmation surface in the app.
///
///   loading  → fetch session by code, verify pending/unexpired
///   review   → show cli_display_name, Approve/Deny
///   pin      → shown only when session-signing doesn't apply (no cached
///              keypair, or the user has PIN-per-payment enabled) — same
///              [SendPinStage] widget, shake-on-error, 5-attempt lockout
///   signing  → session-signing path (cached keypair, no PIN prompt) OR
///              immediately after correct PIN entry: signs the pairing
///              code with the wallet's existing key (Requirement 1.5),
///              retrying signature creation up to 3 attempts on failure
///              before surfacing an error (Requirement 1.6)
///   success  → approved
///   error    → terminal failure (session invalid/expired, signature
///              failed after retries, or a network/server error)
///
/// Deny short-circuits directly from `review` to a denial POST — no
/// signing involved.
enum PairingApprovalStage { loading, review, pin, signing, success, error, denied }

Future<void> showPairingApprovalSheet(
  BuildContext context, {
  required String pairingCode,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => PairingApprovalSheet(pairingCode: pairingCode),
  );
}

class PairingApprovalSheet extends StatefulWidget {
  const PairingApprovalSheet({super.key, required this.pairingCode});

  final String pairingCode;

  @override
  State<PairingApprovalSheet> createState() => _PairingApprovalSheetState();
}

class _PairingApprovalSheetState extends State<PairingApprovalSheet>
    with SingleTickerProviderStateMixin {
  static const int _maxSigningAttempts = 3;

  PairingApprovalStage _stage = PairingApprovalStage.loading;
  String? _sessionId;
  String? _cliDisplayName;
  String? _errorMessage;

  String _pinDigits = '';
  int _pinAttempts = 0;
  String? _pinError;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSession());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _fetchSession() async {
    try {
      final model = ZendScope.of(context);
      final session = await model.walletService.apiClient
          .getCliPairingSessionByCode(widget.pairingCode);

      if (!mounted) return;

      if (session.status != 'pending') {
        setState(() {
          _stage = PairingApprovalStage.error;
          _errorMessage = session.status == 'expired'
              ? 'This pairing request has expired. Please run `zend login` again.'
              : 'This pairing request is no longer available.';
        });
        return;
      }

      setState(() {
        _sessionId = session.sessionId;
        _cliDisplayName = session.cliDisplayName;
        _stage = PairingApprovalStage.review;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = e.statusCode == 404
            ? 'This pairing request could not be found.'
            : e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = 'Could not load pairing request. Check your connection.';
      });
    }
  }

  /// Mirrors `QrPaymentSheet._proceedFromConfirm()`: if a session keypair
  /// is cached and the user hasn't opted into PIN-per-payment, sign
  /// directly with no prompt. Otherwise fall through to the PIN stage.
  /// There is no amount here (unlike a payment), so the amount-threshold
  /// half of `SigningPolicyService.requiresPinForAmount` doesn't apply —
  /// only the PIN-per-payment override is consulted.
  Future<void> _onApproveTap() async {
    final model = ZendScope.of(context);
    final cache = WalletSessionCache.instance;
    final pinPerPaymentEnabled = await model.signingPolicyService.pinPerPaymentEnabled;

    if (!mounted) return;
    if (!pinPerPaymentEnabled && cache.hasKeypair) {
      setState(() => _stage = PairingApprovalStage.signing);
      await _signAndApprove(pin: null, keypairBytes: cache.keypair);
    } else {
      setState(() {
        _pinDigits = '';
        _pinError = null;
        _stage = PairingApprovalStage.pin;
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
    setState(() => _stage = PairingApprovalStage.signing);

    final model = ZendScope.of(context);
    final cache = WalletSessionCache.instance;

    if (cache.hasKeypair) {
      final valid = await model.signingPolicyService.verifyPinAgainstCache(pin, model.walletService);
      if (!valid) {
        if (!mounted) return;
        _handleWrongPin();
        return;
      }
      await _signAndApprove(pin: null, keypairBytes: cache.keypair);
    } else {
      await _signAndApprove(pin: pin, keypairBytes: null);
    }
  }

  void _handleWrongPin() {
    _pinAttempts++;
    if (_pinAttempts >= 5) {
      final model = ZendScope.of(context);
      model.appLockService.lock();
      setState(() {
        _errorMessage = 'Too many incorrect PIN attempts. Please unlock again.';
        _stage = PairingApprovalStage.error;
      });
    } else {
      _shakeController.forward(from: 0);
      setState(() {
        _pinDigits = '';
        _pinError = 'Incorrect PIN';
        _stage = PairingApprovalStage.pin;
      });
    }
  }

  Future<void> _signAndApprove({String? pin, dynamic keypairBytes}) async {
    final model = ZendScope.of(context);

    Uint8List? signature;
    Object? lastError;

    for (var attempt = 1; attempt <= _maxSigningAttempts; attempt++) {
      try {
        signature = await model.walletService.signArbitraryMessage(
          message: widget.pairingCode,
          pin: pin,
          keypairBytes: keypairBytes,
        );
        break;
      } on PinDecryptionException catch (e) {
        // Wrong PIN is not a signing-infrastructure failure — surface it
        // immediately rather than burning retry attempts on it.
        lastError = e;
        signature = null;
        break;
      } catch (e) {
        lastError = e;
        signature = null;
        if (attempt < _maxSigningAttempts) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    if (!mounted) return;

    if (signature == null) {
      if (lastError is PinDecryptionException) {
        _handleWrongPin();
        return;
      }
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = 'Could not sign the approval. Please try again.';
      });
      return;
    }

    try {
      final signatureB64 = base64Encode(signature);
      await model.walletService.apiClient
          .approveCliPairingSession(_sessionId!, signatureB64);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _stage = PairingApprovalStage.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _deny() async {
    if (_sessionId == null) return;
    try {
      final model = ZendScope.of(context);
      await model.walletService.apiClient.denyCliPairingSession(_sessionId!);
    } catch (_) {
      // Best-effort — the session will expire on its own if this fails.
    }
    if (!mounted) return;
    setState(() => _stage = PairingApprovalStage.denied);
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _stage != PairingApprovalStage.signing,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: screenHeight * 0.7,
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
    final zt = ZendTheme.of(context);
    switch (_stage) {
      case PairingApprovalStage.loading:
        return Center(key: const ValueKey('loading'), child: ZendLoader(size: 32));

      case PairingApprovalStage.review:
        return Padding(
          key: const ValueKey('review'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Approve CLI access?',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontStyle: FontStyle.italic,
                  fontSize: 26,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _cliDisplayName ?? 'A CLI',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 15, color: zt.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'is requesting access to create payment requests on your behalf.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 13, color: zt.textSecondary),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(label: 'Approve', onPressed: _onApproveTap),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(label: 'Deny', onPressed: _deny),
              ),
            ],
          ),
        );

      case PairingApprovalStage.pin:
        return SendPinStage(
          key: const ValueKey('pin'),
          amountFormatted: 'CLI access',
          recipientZendtag: _cliDisplayName ?? 'cli',
          note: '',
          pinDigits: _pinDigits,
          pinError: _pinError,
          shakeAnimation: _shakeAnimation,
          shakeController: _shakeController,
          onKey: _onPinKey,
          onBack: () => setState(() {
            _pinDigits = '';
            _pinError = null;
            _stage = PairingApprovalStage.review;
          }),
        );

      case PairingApprovalStage.signing:
        return Center(key: const ValueKey('signing'), child: ZendLoader(size: 32));

      case PairingApprovalStage.success:
        return Center(
          key: const ValueKey('success'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: ZendColors.positive, shape: BoxShape.circle),
                  child: const Icon(SolarIconsBold.checkCircle, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'CLI access approved',
                  style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 24, color: zt.textPrimary),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', onPressed: _dismiss)),
              ],
            ),
          ),
        );

      case PairingApprovalStage.denied:
        return Center(
          key: const ValueKey('denied'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Access denied',
                  style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 24, color: zt.textPrimary),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: PrimaryButton(label: 'Done', onPressed: _dismiss)),
              ],
            ),
          ),
        );

      case PairingApprovalStage.error:
        return Center(
          key: const ValueKey('error'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: ZendColors.destructive, shape: BoxShape.circle),
                  child: const Icon(SolarIconsBold.closeCircle, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: OutlineActionButton(label: 'Close', onPressed: _dismiss)),
              ],
            ),
          ),
        );
    }
  }
}
