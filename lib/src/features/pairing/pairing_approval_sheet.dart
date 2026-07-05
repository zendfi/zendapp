import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../services/wallet_session_cache.dart';

/// Stage machine for the "Pay with Zend" CLI device-pairing approval
/// screen — deliberately smaller than [QrPaymentSheet]'s, since there's no
/// amount to confirm here, just an identity/access decision.
///
///   loading  → fetch session by code, verify pending/unexpired
///   review   → show cli_display_name, Approve/Deny
///   signing  → on Approve: existing biometric/PIN flow signs the pairing
///              code with the wallet's existing key (Requirement 1.5),
///              retrying signature creation up to 3 attempts on failure
///              before surfacing an error (Requirement 1.6)
///   success  → approved
///   error    → terminal failure (session invalid/expired, signature
///              failed after retries, or a network/server error)
///
/// Deny short-circuits directly from `review` to a denial POST — no
/// signing involved.
enum PairingApprovalStage { loading, review, signing, success, error, denied }

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

class _PairingApprovalSheetState extends State<PairingApprovalSheet> {
  static const int _maxSigningAttempts = 3;

  PairingApprovalStage _stage = PairingApprovalStage.loading;
  String? _sessionId;
  String? _cliDisplayName;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSession());
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

  Future<void> _approve() async {
    setState(() => _stage = PairingApprovalStage.signing);

    final model = ZendScope.of(context);
    final cache = WalletSessionCache.instance;

    Uint8List? signature;
    Object? lastError;

    for (var attempt = 1; attempt <= _maxSigningAttempts; attempt++) {
      try {
        if (cache.hasKeypair) {
          signature = await model.walletService.signArbitraryMessage(
            message: widget.pairingCode,
            keypairBytes: cache.keypair,
          );
        } else {
          final pin = await _promptForPin();
          if (pin == null) {
            // User cancelled the PIN prompt — return to review without
            // treating this as a signing failure.
            if (mounted) setState(() => _stage = PairingApprovalStage.review);
            return;
          }
          signature = await model.walletService.signArbitraryMessage(
            message: widget.pairingCode,
            pin: pin,
          );
        }
        break;
      } catch (e) {
        lastError = e;
        signature = null;
        if (attempt < _maxSigningAttempts) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }

    if (signature == null) {
      if (!mounted) return;
      setState(() {
        _stage = PairingApprovalStage.error;
        _errorMessage = lastError is PinDecryptionException
            ? 'Incorrect PIN. Please try again.'
            : 'Could not sign the approval. Please try again.';
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

  Future<String?> _promptForPin() async {
    // Reuses the app's existing PIN entry primitive via SigningPolicyService
    // consumers elsewhere — for the pairing flow specifically, we prompt
    // through a minimal dialog since there's no amount/recipient context to
    // show alongside a full PIN stage. This does not introduce a new
    // cryptographic signing path, only a new (thin) PIN-collection surface
    // in front of the existing signArbitraryMessage call.
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter your PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZendRadii.xxl)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ZendSheetHandle(),
          const SizedBox(height: 20),
          _buildContent(context),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final zt = ZendTheme.of(context);
    switch (_stage) {
      case PairingApprovalStage.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: ZendLoader(size: 32)),
        );

      case PairingApprovalStage.review:
        return Column(
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
              child: PrimaryButton(label: 'Approve', onPressed: _approve),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(label: 'Deny', onPressed: _deny),
            ),
          ],
        );

      case PairingApprovalStage.signing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: ZendLoader(size: 32)),
        );

      case PairingApprovalStage.success:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: ZendColors.positive, shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'CLI access approved',
              style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 24, color: zt.textPrimary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Done', onPressed: _dismiss),
            ),
          ],
        );

      case PairingApprovalStage.denied:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Access denied',
              style: TextStyle(fontFamily: 'InstrumentSerif', fontSize: 24, color: zt.textPrimary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: 'Done', onPressed: _dismiss),
            ),
          ],
        );

      case PairingApprovalStage.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: ZendColors.destructive, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DMSans', fontSize: 14, color: zt.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlineActionButton(label: 'Close', onPressed: _dismiss),
            ),
          ],
        );
    }
  }
}
