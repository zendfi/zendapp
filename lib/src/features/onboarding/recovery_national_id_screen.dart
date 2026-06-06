import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../core/zend_state.dart';
import '../../navigation/zend_routes.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/recovery_service.dart';
import 'recovery_new_pin_screen.dart';

/// Asks for the National ID number to decrypt the recovery packet.
///
/// Called after OTP verification in the Forgot PIN flow.
/// On success, navigates to [RecoveryNewPinScreen] with the decrypted keypair.
class RecoveryNationalIdScreen extends StatefulWidget {
  const RecoveryNationalIdScreen({super.key, required this.recoveryToken});

  final String recoveryToken;

  @override
  State<RecoveryNationalIdScreen> createState() =>
      _RecoveryNationalIdScreenState();
}

class _RecoveryNationalIdScreenState extends State<RecoveryNationalIdScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  int _attempts = 0;
  static const int _maxAttempts = 3;
  DateTime? _lockedUntil;

  bool get _isLockedOut {
    if (_lockedUntil == null) return false;
    return DateTime.now().isBefore(_lockedUntil!);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLockedOut) return;

    final nationalId = _controller.text.trim().replaceAll(RegExp(r'\s'), '');
    if (nationalId.isEmpty) {
      setState(() => _error = 'Please enter your ID number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final model = ZendScope.of(context);
      final keypair = await model.recoveryService.decryptRecoveryPacket(nationalId);

      if (!mounted) return;

      pushAndRemoveUntilZendSlide(
        context,
        RecoveryNewPinScreen(
          recoveryToken: widget.recoveryToken,
          recoveredKeypair: keypair,
        ),
      );
    } on RecoveryDecryptionException {
      if (!mounted) return;
      _attempts++;
      if (_attempts >= _maxAttempts) {
        _lockedUntil = DateTime.now().add(const Duration(minutes: 30));
        setState(() {
          _error = 'Too many incorrect attempts. Please try again in 30 minutes.';
          _controller.clear();
        });
        // Best-effort alert
        try {
          final model = ZendScope.of(context);
          await model.walletService.apiClient.recoveryInit();
        } catch (_) {}
      } else {
        setState(() {
          _error = 'Incorrect ID. ${_maxAttempts - _attempts} attempt(s) remaining.';
          _controller.clear();
        });
      }
    } on RecoveryPacketNotFoundException {
      if (!mounted) return;
      setState(() => _error =
          'No recovery backup found. Make sure you\'re signed into the same Google or iCloud account.');
    } on CloudBackupException catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not access cloud storage: ${e.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // textOnDeepSecondary / textOnDeepMuted / bgDeepElevated are not in ZendColors —
    // we use the raw hex values that match the existing lock screen style.
    const textOnDeepSecondary = Color(0x99E8F4EC);
    const textOnDeepMuted = Color(0x66E8F4EC);
    const bgDeepElevated = Color(0xFF1C2E22);

    return Scaffold(
      backgroundColor: ZendColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: ZendColors.textOnDeep),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter your government ID',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 26,
                  color: ZendColors.textOnDeep,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the government ID number you used when setting up recovery.',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  height: 1.5,
                  color: textOnDeepSecondary,
                ),
              ),
              const SizedBox(height: 28),

              TextField(
                controller: _controller,
                enabled: !_isLockedOut,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\s\-A-Za-z]')),
                ],
                autofocus: true,
                style: const TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 20,
                  letterSpacing: 2,
                  color: ZendColors.textOnDeep,
                ),
                decoration: InputDecoration(
                  hintText: 'Government ID number',
                  hintStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 14,
                    color: textOnDeepMuted,
                    letterSpacing: 0,
                  ),
                  filled: true,
                  fillColor: bgDeepElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: ZendColors.accentPop,
                      width: 1.5,
                    ),
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    color: ZendColors.destructive,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),

              if (!_isLockedOut && _attempts > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${_maxAttempts - _attempts} attempt(s) remaining',
                  style: const TextStyle(
                    fontFamily: 'DMMono',
                    fontSize: 11,
                    color: textOnDeepMuted,
                  ),
                ),
              ],

              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 13, color: textOnDeepMuted),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your ID is used locally to decrypt — never sent to Zend.',
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontSize: 12,
                        color: textOnDeepMuted,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              if (_loading)
                const Center(
                  child: CircularProgressIndicator(
                    color: ZendColors.accentPop,
                  ),
                )
              else if (!_isLockedOut)
                PrimaryButton(
                  label: 'Continue',
                  onPressed: _submit,
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
