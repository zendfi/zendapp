import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'src/core/zend_state.dart';
import 'src/data/local/app_database.dart';
import 'src/models/notification_destination.dart';
import 'src/services/api_client.dart';
import 'src/features/deeplink/deep_link_handler.dart';
import 'src/services/pending_notification_service.dart';
import 'src/services/app_lock_service.dart';
import 'src/services/auth_service.dart';
import 'src/services/push_notification_service.dart';
import 'src/services/recent_contacts_store.dart';
import 'src/services/sound_service.dart';
import 'src/services/sse_service.dart';
import 'src/services/wallet_service.dart';
import 'src/services/payment_rails.dart';
import 'src/services/sui_oauth_provider.dart';
import 'src/services/sui_salt_custody_service.dart';
import 'src/services/sui_zklogin_service.dart';
import 'src/services/zendtag_service.dart';
import 'src/services/transfer_service.dart';
import 'src/services/fx_service.dart';
import 'src/services/savings_service.dart';
import 'src/services/pocket_service.dart';
import 'src/services/email_intent_service.dart';

const kApiBaseUrl = 'https://api.usezend.app';

/// Google OAuth client used for zkLogin sign-in.
///
/// **This must be the Web client id, and it must be the same value on every
/// platform.** A zkLogin Sui address is derived from `iss`, `aud`, `sub`, and the
/// user salt, and `aud` is this client id. Two client ids therefore produce two
/// different Sui addresses for the same Google account, and funds sent to one are
/// not spendable from the other.
///
/// The Android client id cannot be used here: Google documents the browser-based
/// OAuth flow for iOS and Desktop client types only, and directs Android to the
/// native Credential Manager SDK — which cannot set the OIDC `nonce` that zkLogin
/// requires. A Web client id is also the only kind a browser can use, so it is
/// the only value that lets zendapp and zendonline share one address.
///
/// `SUI_ZKLOGIN_GOOGLE_CLIENT_IDS` on the backend must contain this exact value,
/// or ID token verification fails on the `aud` claim.
const kZkLoginGoogleClientId =
    '896122105196-b2n7pk8f6brvngro80np66f99bh7vi8u.apps.googleusercontent.com';

/// Redirect target for the zkLogin OAuth round-trip.
///
/// Must be registered verbatim as an Authorized redirect URI on the Web client.
/// Google only accepts https redirects for a Web client, so this is an App Link
/// (Android) / Universal Link (iOS) rather than a custom scheme.
const kZkLoginRedirectUri = 'https://zdfi.me/auth/callback';
const kZkLoginRedirectHost = 'zdfi.me';
const kZkLoginRedirectPath = '/auth/callback';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the native (pre-Flutter-engine) splash on screen past Flutter's
  // first frame — normally it's dismissed the instant Flutter paints
  // anything, which used to hand off to our separate Dart SplashScreen
  // widget. That handoff is an uncontrollable hard cut (Flutter dropped the
  // old crossfade mechanism), so instead we hold the *native* splash in
  // place for the whole session-restore sequence and call
  // FlutterNativeSplash.remove() once _SplashWithSessionRestore in app.dart
  // has actually decided where to navigate. Net effect: one splash, not two.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Catch any Flutter framework errors and log them instead of crashing silently
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('${details.stack}');
  };

  // Started here but deliberately NOT awaited yet. Initialising the native
  // Firebase SDK is one of the most expensive things on the launch path, and
  // nothing between this line and the Future.wait further down needs it —
  // service construction below is all plain synchronous constructors. The one
  // thing that does need it (reading a notification tap that cold-launched
  // us) is chained onto this future at that Future.wait, so Firebase init
  // overlaps with the keychain and SharedPreferences reads instead of running
  // strictly before them.
  final firebaseReady = _initFirebase();

  // Pre-warm audio — completely non-fatal
  SoundService.init().ignore();

  const secureStorage = FlutterSecureStorage();

  final apiClient = ApiClient(
    baseUrl: kApiBaseUrl,
    secureStorage: secureStorage,
  );

  final authService = AuthService(
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  final walletService = WalletService(
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  final zendtagService = ZendtagService(apiClient: apiClient);

  // zkLogin sign-in. The Web client id and https redirect are required together:
  // Google permits only https redirects for a Web client, and the Web client is
  // the only kind a browser can use — which is what keeps one Google account
  // mapped to one Sui address across app and web, since `aud` feeds the address.
  // 2-of-3 salt custody: share A here, share B in the user's Drive, share C on
  // the backend. Any two reconstruct the salt, so no single holder disappearing —
  // including us — can permanently lock a user out of their funds.
  final saltCustody = SuiSaltCustodyService(
    apiClient: apiClient,
    secureStorage: secureStorage,
  );

  final zkLoginService = SuiZkLoginService(
    apiClient: apiClient,
    saltCustody: saltCustody,
    oauthProvider: GoogleZkLoginOAuthProvider(
      clientId: kZkLoginGoogleClientId,
      redirectUri: kZkLoginRedirectUri,
      // 'https' selects App Link / Universal Link capture; host and path are
      // mandatory on Android in flutter_web_auth_2 5.x when the scheme is https.
      callbackUrlScheme: 'https',
      httpsHost: kZkLoginRedirectHost,
      httpsPath: kZkLoginRedirectPath,
      // Implicit, because zkLogin needs only an ID token. A code exchange would
      // require the Web client's secret, which must never ship in an app.
      flow: SuiOAuthFlow.implicitIdToken,
    ),
  );

  final solanaRail = PaymentRailBinding(
    identity: SolanaWalletIdentity(walletService: walletService),
    signer: SolanaTransactionSigner(walletService: walletService),
    client: CapabilityGatedSolanaRailClient(apiClient: apiClient),
  );
  // All three components must agree on the network or PaymentRailBinding rejects
  // the mix. This must also match the backend's SUI_NETWORK: the rail policy
  // compares the requested network against the cohort's, so a mismatch is denied
  // rather than silently routed.
  // Testnet until a funding route onto Sui mainnet exists. Mainnet USDC cannot
  // currently reach a user's Sui address — there is no native ramp and the
  // Solana-to-Sui path is unbuilt — so a mainnet rail would be provably correct
  // and unreachable. Flip this and SUI_NETWORK together; a mismatch is denied by
  // rail policy, and the client silently falls back to Solana, which for a
  // zkLogin account surfaces as the wrong error entirely.
  const suiNetwork = PaymentNetwork.testnet;
  final suiRail = PaymentRailBinding(
    identity: SuiWalletIdentity(apiClient: apiClient, network: suiNetwork),
    signer: SuiTransactionSigner(
      zkLoginService: zkLoginService,
      network: suiNetwork,
    ),
    client: SuiV2RailClient(apiClient: apiClient, network: suiNetwork),
  );

  // Both rails are registered; which one a transfer actually uses is decided at
  // runtime from /capabilities, never hardcoded here. The registry stays
  // fail-closed, so an unavailable rail raises rather than silently crossing
  // chains.
  final railRegistry = PaymentRailRegistry([solanaRail, suiRail]);
  final selectedRail = railRegistry.resolve(PaymentRail.solana);

  final railRouter = RailRouter(apiClient: apiClient, registry: railRegistry);

  final transferService = TransferService(
    // Fixed pair is the fallback used only when capabilities cannot be read.
    railClient: selectedRail.client,
    transactionSigner: selectedRail.signer,
    railRouter: railRouter,
  );

  final fxService = FxService(apiClient: apiClient);

  final recentContactsStore = RecentContactsStore(secureStorage: secureStorage);

  final sseService = SseService(
    baseUrl: kApiBaseUrl,
    secureStorage: secureStorage,
  );

  final pushNotificationService = PushNotificationService(apiClient: apiClient);

  final appLockService = AppLockService();

  final savingsService = SavingsService(apiClient: apiClient);

  final pocketService = PocketService(apiClient: apiClient);

  final emailIntentService = EmailIntentService(
    apiClient: apiClient,
    walletService: walletService,
  );

  // Initialise the local SQLite database (warm up the connection).
  final localDb = AppDatabase.instance;

  final model = ZendAppModel(
    authService: authService,
    walletService: walletService,
    zendtagService: zendtagService,
    transferService: transferService,
    fxService: fxService,
    recentContactsStore: recentContactsStore,
    sseService: sseService,
    pushNotificationService: pushNotificationService,
    appLockService: appLockService,
    savingsService: savingsService,
    pocketService: pocketService,
    emailIntentService: emailIntentService,
    localDb: localDb,
    zkLoginService: zkLoginService,
  );

  // Wire every confirmed 401 (from any API call, on any screen) to a
  // deterministic sign-out. Navigation itself is handled by app.dart via
  // model.onForcedSignOut, set once the navigator key is available — see
  // zendapp-hardening spec Req 1.4.
  apiClient.onUnauthorized = model.handleUnauthorized;

  // Register pool message badge callback early — before auth — so FCM messages
  // that arrive before authentication completes still mark the pool as unread.
  PushNotificationService.onPoolMessageReceived = (poolId) {
    model.poolsWithNewMessages.add(poolId);
    model.triggerRebuild();
  };

  // Everything still needed before the first frame, run concurrently.
  //
  // These are mutually independent — no one of them consumes another's
  // result — but each is a platform-channel round trip (keychain,
  // SharedPreferences, app_links, FCM) and they used to run strictly one
  // after another while the native splash was held on screen. On a cold
  // process the first keychain access is the expensive one, and stacking
  // these serially meant paying every latency in sequence.
  //
  // The notification-tap read stays gated on Firebase being up, but only on
  // that — it no longer waits for the storage reads, and they no longer wait
  // for it.
  await Future.wait<void>([
    model.hydrateRecentContacts(),
    model.loadPersistedPreferences(),
    DeepLinkHandler.init(),
    // Must still complete BEFORE runApp so the destination is parked in
    // PendingNotificationService before the widget tree builds.
    firebaseReady.then((_) => _checkInitialNotificationTap()),
  ]);

  runApp(ZendApp(model: model));
}

/// Brings up Firebase and registers the background message handler.
///
/// Swallows its own failures rather than propagating them: Firebase being
/// unavailable costs push notifications, not the app, and because the
/// returned future is not awaited immediately an escaping error would
/// surface as an unhandled async exception instead.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase init failure is non-fatal — app works without push notifications
    debugPrint('Firebase init failed: $e');
  }
}

/// Checks Firebase's `getInitialMessage` for a notification tap that cold-launched
/// the app, and parks the parsed destination in [PendingNotificationService].
/// Called before `runApp` so the destination is available immediately when the
/// widget tree builds — avoiding the race between `initialize()` (post-auth) and
/// `app.dart`'s `initState` postFrameCallback.
Future<void> _checkInitialNotificationTap() async {
  try {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) {
      final destination = NotificationDestination.fromData(message.data);
      PendingNotificationService.store(destination);
    }
  } catch (_) {
    // Non-fatal — notification tap simply won't deep-link if this fails.
  }
}
