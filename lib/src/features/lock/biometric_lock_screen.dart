import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/biometric_service.dart';

/// App lock for accounts that have no PIN.
///
/// The existing [AppLockOverlay] cannot serve a zkLogin account: it verifies a
/// PIN by decrypting a locally stored Solana key, and such an account has
/// neither. This gate asks the OS to confirm the holder instead.
///
/// There is no in-app fallback code, and deliberately so — inventing one would
/// mean inventing a recovery path for it, and any such path would be a way around
/// the lock. The OS passcode is the fallback, which the platform already handles.
/// "Sign out" remains available so a user who genuinely cannot authenticate is
/// never trapped; they lose nothing, because signing back in with Google restores
/// the same account and the same Sui address.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.onUnlocked});

  /// Invoked once the holder is confirmed. Navigation is the caller's choice, so
  /// this screen works both as a launch gate and as a resume gate.
  final VoidCallback onUnlocked;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  final _biometrics = BiometricService();
  bool _prompting = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Prompt immediately: for an enabled lock this is the only thing standing
    // between launch and the app, so making the user tap first is friction with
    // no purpose.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_prompting) return;
    setState(() {
      _prompting = true;
      _failed = false;
    });

    final ok = await _biometrics.authenticateOnly(reason: 'Unlock Zend!');
    if (!mounted) return;

    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _prompting = false;
      _failed = true;
    });
  }

  Future<void> _signOut() async {
    final model = ZendScope.read(context);
    await model.authService.logout();
    if (!mounted) return;
    // resetState clears per-user state; onForcedSignOut drives navigation back to
    // the welcome screen through the global navigator.
    model.handleUnauthorized();
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    PhosphorIconsRegular.lockKey,
                    size: 44,
                    color: zt.textPrimary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Zend! is locked',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: zt.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _failed
                        ? 'Authentication was cancelled or failed.'
                        : 'Confirm it’s you to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: zt.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Unlock',
                    isLoading: _prompting,
                    onPressed: _authenticate,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _prompting ? null : _signOut,
                    child: Text(
                      'Sign out',
                      style: TextStyle(color: zt.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
