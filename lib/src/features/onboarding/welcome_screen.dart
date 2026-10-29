import 'dart:async';

// kIsWeb and debugPrint live in foundation.dart; material.dart does not
// re-export them.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_mark.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../models/api_exceptions.dart';
import '../../navigation/zend_routes.dart';
import '../../services/sui_oauth_provider.dart';
import '../../services/sui_zklogin_models.dart';
import '../../services/sui_zklogin_service.dart';
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

  /// A zkLogin session minted before the user taps, so the OAuth popup opens
  /// with the tap's user activation still intact.
  ///
  /// Web only, and not an optimisation. `flutter_web_auth_2` opens a popup on
  /// web, browsers only allow that while the triggering gesture is active, and
  /// minting the session is a network round-trip that outlives the gesture.
  /// Doing it inside the handler meant the popup opened unattributed: Chrome on
  /// Android permitted it (it opens a tab, not a popup), Chrome on desktop
  /// blocked it, and Safari blocked it without ever settling the future — a
  /// permanent spinner. Preparing ahead of time leaves nothing to await
  /// between the tap and `window.open`.
  PreparedZkLoginSignIn? _prepared;

  @override
  void initState() {
    super.initState();
    // ZendScope.read rather than .of: .of throws from initState, which
    // zend_scope_read_test.dart pins down explicitly.
    if (kIsWeb) unawaited(_prepareSession());
  }

  @override
  void dispose() {
    // Holds live key material, so it is never just dropped.
    _prepared?.dispose();
    _prepared = null;
    super.dispose();
  }

  Future<void> _prepareSession() async {
    final model = ZendScope.read(context);
    try {
      final prepared = await model.zkLoginService.preparePublicSignIn();
      if (!mounted) {
        prepared.dispose();
        return;
      }
      _prepared?.dispose();
      _prepared = prepared;
    } catch (error) {
      // Not surfaced. A failed pre-warm only costs the popup its activation;
      // the tap still falls back to minting a session inline, which is exactly
      // the old behaviour rather than a new failure.
      debugPrint('zkLogin session pre-warm failed: $error');
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final model = ZendScope.of(context);
    final navigator = Navigator.of(context);

    // Consumed here: completePublicSignIn takes ownership on success and
    // disposes on failure, so the field must not keep pointing at it.
    final prepared = _prepared;
    _prepared = null;
    final usable = prepared != null && prepared.isUsable;
    if (prepared != null && !usable) prepared.dispose();

    try {
      final result = await model.authService.signInWithGoogle(
        model.zkLoginService,
        prepared: usable ? prepared : null,
      );
      if (!mounted) return;

      // Prefer the Google profile name. Falling back to the handle would show a
      // placeholder user their own email address as their display name.
      final displayName = result.displayName.trim().isNotEmpty
          ? result.displayName
          : result.zendtag;

      // Set BEFORE setAuthenticated, which is not passive: it calls startPolling()
      // and kicks off unawaited balance/history/pool fetches synchronously. Setting
      // these afterwards let the first balance fetch race ahead of them, fall back
      // to Solana, and fail with WALLET_NOT_REGISTERED.
      //
      // A zkLogin account has no local keypair and no PIN, so the inactivity lock
      // must stay disarmed — arming it would present a lock screen that cannot be
      // satisfied. App lock is opt-in from profile settings instead.
      model.appLockService.pinIsAvailable = false;
      model.isZkLoginAccount = true;
      // No Solana wallet exists for this account, so falling back to Solana would
      // fail with an error about storing a wallet backup — wrong cause, and nothing
      // the user can act on.
      model.transferService.accountUsesLocalKeyRail = false;

      model.setAuthenticated(
        userId: result.userId,
        zendtag: result.zendtag,
        displayName: displayName,
        zendtagIsPlaceholder: result.zendtagIsPlaceholder,
      );

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
    } catch (error) {
      // Anything reaching here is not one of the typed failures above, so it
      // carries no user-facing message of its own. It used to be swallowed
      // entirely, which made the single most common web failure mode
      // undiagnosable: the user saw "Please try again" and the console showed
      // only a bare `Uncaught Exception {}`.
      //
      // The usual cause on web is an unregistered redirect URI.
      // `kZkLoginWebRedirectUri` is derived from `Uri.base.origin`, while
      // Google only accepts redirect URIs registered on the OAuth client —
      // currently just https://app.usezend.app/auth.html and
      // https://zdfi.me/auth/callback. From a preview deployment, localhost,
      // or the apex/www host, Google answers redirect_uri_mismatch *inside the
      // popup*, so auth.js never posts back and `authenticate()` either throws
      // when the popup is closed or never completes at all.
      //
      // The message stays generic for the user; the detail goes to the console,
      // where it is the difference between a five-minute fix and a day of
      // bisecting CSP headers. The thrown object is logged rather than
      // interpolated into the UI because an OAuth error can echo request
      // parameters back.
      if (kIsWeb) {
        // Recomputed rather than imported from main.dart: importing the entry
        // point from a feature file would close a cycle back through app.dart.
        // This mirrors kZkLoginWebRedirectUri exactly.
        debugPrint(
          'Google sign-in failed on web. Origin: ${Uri.base.origin}. '
          'Redirect URI sent: ${Uri.base.origin}/auth.html. '
          'If that origin is not registered on the OAuth client, Google '
          'rejects it inside the popup and the callback never returns. '
          'Underlying error: $error',
        );
      } else {
        debugPrint('Google sign-in failed: $error');
      }
      if (!mounted) return;
      setState(() => _error = "Couldn't sign you in. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
      // Re-warm only after a failure, and only while still on this screen.
      //
      // The nonce is single-use, so a retry does need a fresh session — but
      // re-warming unconditionally minted one on success too, moments before
      // the app navigates away and discards it. That showed up as seven
      // `session_requested` rows for two actual sign-ins, and each wasted
      // request is another one the browser can abort mid-flight while the
      // OAuth popup has focus.
      if (mounted && kIsWeb && _error != null && _prepared == null) {
        unawaited(_prepareSession());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        // A Stack — not a single Column with Spacers — so the title block
        // and the button block size and position completely
        // independently. With Spacers in one Column, the title's position
        // is a function of how tall the button block below it is (error
        // text appearing/disappearing shifts everything); centering the
        // title on the full screen height here means it truly never moves
        // regardless of what the bottom block does.
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand moment: the Z mark, slowly sweeping.
                      const ZendMark(size: 88, animate: true),
                      const SizedBox(height: 28),
                      Text(
                        'Welcome to Zend',
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 44,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: zt.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "The internet's social money network.",
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 17,
                          color: zt.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                            fontFamily: 'Geist',
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
          ],
        ),
      ),
    );
  }
}
