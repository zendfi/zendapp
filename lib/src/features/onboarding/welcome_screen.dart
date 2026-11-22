import 'dart:async';
import 'dart:math' as math;

// kIsWeb and debugPrint live in foundation.dart; material.dart does not
// re-export them.
import '../deeplink/deep_link_handler.dart' show DeepLinkPayload;
import '../links/cash_widgets.dart' show showCashCodeEntrySheet;
import '../links/my_links_screen.dart' show zlinkServiceOf;
import '../links/zlink_sheets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/zend_state.dart';
import '../../design/zend_drawn.dart';
import '../../design/zend_mark.dart';
import '../../design/zend_avatar.dart';
import '../../core/zend_format.dart';
import '../../design/zend_motion_widgets.dart' show ZendBlurSwap, ZendRise;
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
  /// Bumped when a typed cash code becomes the pending link, so the line
  /// above the button reloads for it.
  int _pendingVersion = 0;

  Future<void> _enterCashCode() async {
    // Opens it right in the sheet (signed out is fine), so a wrong code is
    // fixed there; the line above the button then says who sent what.
    final opened = await showCashCodeEntrySheet(
      context,
      open: zlinkServiceOf(context).openCash,
    );
    if (opened == null || !mounted) return;
    PendingZlink.store(
      DeepLinkPayload(zendtag: '', cashCode: opened.code.compact),
    );
    setState(() => _pendingVersion++);
  }

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

  /// True while [_prepareSession] is in flight, so the button can show itself
  /// as busy instead of letting a tap through to the path that cannot work.
  ///
  /// Without this the first tap after load raced the pre-warm: the field was
  /// still null, the handler fell back to minting inline, and Safari hung for
  /// the full five-minute callback timeout.
  bool _preparing = false;

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
    if (_preparing) return;
    final model = ZendScope.read(context);
    if (mounted) setState(() => _preparing = true);
    try {
      final prepared = await model.zkLoginService.preparePublicSignIn();
      if (!mounted) {
        prepared.dispose();
        return;
      }
      _prepared?.dispose();
      _prepared = prepared;
    } catch (error) {
      // Still not surfaced on its own: the button reports "getting ready" and
      // the next tap retries. What must not happen is falling through to the
      // inline path, which cannot open a window under Safari.
      debugPrint('zkLogin session pre-warm failed: $error');
    } finally {
      if (mounted) setState(() => _preparing = false);
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

    // On web, refuse to continue without a session already in hand. Falling
    // back to minting one here is what hung Safari: the round-trip spends the
    // tap's user activation, `window.open` is then blocked, and nothing ever
    // writes the callback the plugin is polling for — so it spins for the full
    // five-minute timeout with no error. Better to re-arm and let the user tap
    // again a moment later.
    if (kIsWeb && !usable) {
      unawaited(_prepareSession());
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Almost ready — tap again in a second.';
        });
      }
      return;
    }

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

      // Read before setAuthenticated, which hands the held link to the app.
      // A money link (send, request, cash) opens the moment sign-in finishes;
      // the username offer and the notifications prompt wait until it's done
      // (see openZlink) rather than stacking on top of the money.
      final arrivedByLink = PendingZlink.peek?.isZlink == true;
      model.holdPromptsForLink = arrivedByLink;

      model.setAuthenticated(
        userId: result.userId,
        zendtag: result.zendtag,
        displayName: displayName,
        zendtagIsPlaceholder: result.zendtagIsPlaceholder,
      );

      // Not awaited: this future only completes when the shell is popped,
      // which never happens, so anything after an await never ran.
      unawaited(
        navigator.pushAndRemoveUntil(
          zendRoute<void>(page: const ZendShell()),
          (route) => false,
        ),
      );

      // Offered *after* the shell is in place, so the account is already usable
      // behind the sheet and dismissing it costs the user nothing. Returning
      // users, and anyone who has already declined, are never asked.
      if (!result.shouldOfferZendtag) return;
      if (arrivedByLink) {
        model.zendtagOfferAfterLink = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!navigator.mounted || !model.zendtagIsPlaceholder) return;
      await showZendtagPromptSheet(navigator.context);
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
        // The redirect-URI hint is conditional on purpose.
        //
        // It used to print unconditionally, which made every web failure look
        // like an unregistered origin and cost real time chasing the wrong
        // cause. The two failures are distinguishable: an unregistered
        // redirect URI means Google *answers* and rejects inside the popup, so
        // a response exists. A NetworkException means no response arrived at
        // all — nothing reached Google, so its OAuth config cannot be the
        // reason.
        //
        // Origin is recomputed rather than imported from main.dart, because
        // importing the entry point from a feature file would close a cycle
        // back through app.dart. It mirrors kZkLoginWebRedirectUri exactly.
        final transportFailed =
            error is NetworkException || error is RequestTimeoutException;
        final hint = transportFailed
            ? 'The request did not reach the server, so this is transport, not '
                  'OAuth configuration. Usual causes: a deploy rolling over '
                  '(a single-task service has no healthy target mid-rollout), '
                  'or a browser extension intercepting fetch.'
            : 'If this origin is not registered on the OAuth client, Google '
                  'rejects it inside the popup and the callback never returns.';
        debugPrint(
          'Google sign-in failed on web. Origin: ${Uri.base.origin}. '
          'Redirect URI sent: ${Uri.base.origin}/auth.html. '
          '$hint Underlying error: $error',
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
    final title = TextStyle(
      fontFamily: 'Geist',
      fontSize: 44,
      height: 1.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -44 * 0.055,
      color: zt.textPrimary,
    );
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
                      // zend-site's hero: a Zend note that lands somewhere new
                      // every few seconds, in that person's money. Falls back
                      // to the Z mark where the screen is too short for it.
                      const ZendRise(child: _LandingNote()),
                      const SizedBox(height: 28),
                      // zend-site's hero: a firm line, then a light one with
                      // the signal underline drawn under it.
                      ZendRise(
                        delay: const Duration(milliseconds: 80),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Cash that works', style: title),
                        ),
                      ),
                      ZendRise(
                        delay: const Duration(milliseconds: 200),
                        child: ZendSwooshText(
                          'anywhere.',
                          style: title.copyWith(fontWeight: FontWeight.w300),
                          delay: const Duration(milliseconds: 900),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ZendRise(
                        delay: const Duration(milliseconds: 320),
                        child: Text(
                          'Social, borderless and as easy as a text.',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 18,
                            color: zt.textSecondary,
                            height: 1.5,
                          ),
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
                      // "Tolu sent you ₦8,000" when opened from a Zlink.
                      ZlinkWelcomeLine(key: ValueKey(_pendingVersion)),
                      PrimaryButton(
                        label: 'Continue with Google',
                        // Also busy while the pre-warm is in flight, so the
                        // common case is simply waiting a beat rather than
                        // tapping into the guard above.
                        isLoading: _busy || _preparing,
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
                      const SizedBox(height: 8),
                      // Someone was handed a cash code: it opens here, and
                      // lands in their balance once they're in.
                      TextButton(
                        onPressed: _busy ? null : _enterCashCode,
                        child: Text(
                          'Have a cash code?',
                          style: TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: zt.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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

/// The site's hero note on the welcome screen: the same \$25 from Amara,
/// landing with someone new every 2.6s, shown in their own money. Example
/// rates, like the site; the app uses the day's once you're in. Still under
/// Reduce Motion, and it stops while the screen isn't showing.
class _LandingNote extends StatefulWidget {
  const _LandingNote();

  @override
  State<_LandingNote> createState() => _LandingNoteState();
}

class _LandingNoteState extends State<_LandingNote> {
  // zend-site lib/people.ts and lib/money.ts: who, where, their money, and
  // an example rate per dollar.
  static const _stops = <(String, String, String, double)>[
    ('Léa', 'Lisbon', 'EUR', 0.87),
    ('Kenji', 'Tokyo', 'JPY', 150),
    ('Mum', 'Mumbai', 'INR', 85),
    ('Rafa', 'São Paulo', 'BRL', 5.5),
    ('Kemi', 'Lagos', 'NGN', 1500),
    ('Minji', 'Seoul', 'KRW', 1400),
    ('Wanjiru', 'Nairobi', 'KES', 129),
    ('Yuri', 'the Moon', 'USD', 1),
  ];
  static const _usd = 25.0;

  int _i = 0;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (ZendMotion.reduced(context)) return;
    _timer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      final showing =
          (ModalRoute.of(context)?.isCurrent ?? true) &&
          TickerMode.valuesOf(context).enabled &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
      if (showing) setState(() => _i = (_i + 1) % _stops.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _money(double usd, String code, double perUsd) =>
      '${CurrencyStyle.prefixOf(code)}${groupThousands((usd * perUsd).round().toString())}';

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Room left once the title, the lede and the buttons have theirs.
    final byHeight = (screen.height - 500 - 76) * 1.72;
    final width = [340.0, screen.width - 48 - 28, byHeight].reduce(math.min);
    if (width < 200) return const ZendMark(size: 88, animate: true);

    final (name, place, code, rate) = _stops[_i];
    final amount = _money(_usd, code, rate);
    final where = place == 'the Moon' ? 'on the Moon' : 'in $place';
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZendBanknote(
            width: width,
            line: 'From Amara · “first round’s on me 🍻”',
            amount: ZendBlurSwap(
              swapKey: amount,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  amount,
                  style: ZendTextStyles.displayXl.copyWith(
                    fontSize: width * 0.17,
                    letterSpacing: -width * 0.17 * 0.055,
                    color: ZendBanknote.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ZendBlurSwap(
            swapKey: name,
            child: _LandedPill(name: name, where: where),
          ),
        ],
      ),
    );
  }
}

/// "Landed with Léa in Lisbon", with her face (zend-site's `.note-landed`).
class _LandedPill extends StatelessWidget {
  const _LandedPill({required this.name, required this.where});

  final String name;
  final String where;

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      decoration: BoxDecoration(
        color: zt.bgCard,
        borderRadius: BorderRadius.circular(ZendRadii.pill),
        boxShadow: ZendShadows.lift(zt),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZendAvatar(radius: 14, initials: name, seed: name),
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Landed with '),
                TextSpan(
                  text: name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' $where'),
              ],
            ),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              color: zt.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
