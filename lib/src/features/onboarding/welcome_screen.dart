import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../../services/sui_oauth_provider.dart';
import '../../services/sui_zklogin_models.dart';
import '../shell/zend_shell.dart';
import 'zendtag_prompt_sheet.dart';

/// Entry point for a signed-out device.
///
/// Sign-in is a single step: Google returns an ID token, and the backend creates
/// or resolves the account and mints a Zend session in one call. There is no OTP,
/// no email verification, and no handle picker on this path — a new user reaches
/// a usable, addressable account without anything that feels like a signup.
///
/// The OTP screens still exist and still work; they are simply no longer reachable
/// from here. Nothing about them was deleted, so the previous flow remains
/// available for accounts that predate zkLogin.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final model = ZendScope.of(context);
    final navigator = Navigator.of(context);

    try {
      final result = await model.authService.signInWithGoogle(
        model.zkLoginService,
      );
      if (!mounted) return;

      // Prefer the Google profile name. Falling back to the handle would show a
      // placeholder user their own email address as their display name.
      final displayName = result.displayName.trim().isNotEmpty
          ? result.displayName
          : result.zendtag;

      model.setAuthenticated(
        userId: result.userId,
        zendtag: result.zendtag,
        displayName: displayName,
        zendtagIsPlaceholder: result.zendtagIsPlaceholder,
      );

      // A zkLogin account has no local keypair and no PIN, so the inactivity lock
      // must stay disarmed — arming it would present a lock screen that cannot be
      // satisfied. App lock is opt-in from profile settings instead.
      model.appLockService.pinIsAvailable = false;
      model.isZkLoginAccount = true;

      await navigator.pushAndRemoveUntil(
        zendRoute<void>(page: const ZendShell()),
        (route) => false,
      );

      // Offered *after* the shell is in place, so the account is already usable
      // behind the sheet and dismissing it costs the user nothing. Returning
      // users, and anyone who has already declined, are never asked.
      if (!mounted || !result.shouldOfferZendtag) return;
      final shellContext = navigator.context;
      if (!shellContext.mounted) return;
      await showZendtagPromptSheet(shellContext);
    } on SuiOAuthException catch (e) {
      // Covers a cancelled or failed Google round-trip.
      if (!mounted) return;
      setState(() => _error = e.message);
    } on SuiZkLoginIdentityConflict catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't sign you in. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: ZendScrollPage(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 96),
                    Text(
                      'Send money,\nanywhere.',
                      style: TextStyle(
                        fontFamily: 'CircularStd',
                        fontSize: 56,
                        height: 1.08,
                        fontWeight: FontWeight.w700,
                        color: zt.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'To anyone, in any country, instantly.',
                      style: TextStyle(
                        fontSize: 16,
                        color: zt.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 36),
                    PrimaryButton(
                      label: 'Continue with Google',
                      isLoading: _busy,
                      onPressed: _continueWithGoogle,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'CircularStd',
                          fontSize: 13,
                          color: ZendColors.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Signing in creates your account if you don’t have one yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: zt.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
