import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../models/notification_category.dart';
import '../models/notification_destination.dart';
import '../models/payment_request_notification.dart';
import 'api_client.dart';
import 'pending_notification_service.dart';

class PushNotificationService {
  final ApiClient _apiClient;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Pending payment request from a notification tap (background/terminated).
  /// Consumed once by the app after session restore.
  static PaymentRequestNotification? pendingPaymentRequestFromNotification;

  /// Held so [dispose] can actually cancel this subscription. The previous
  /// implementation called `FirebaseMessaging.onMessage.drain()` in dispose(),
  /// which does NOT cancel the listener registered in
  /// [_listenForForegroundMessages] — `drain()` only consumes a stream's
  /// remaining events on the caller's own new subscription, an unrelated
  /// stream subscription to the same broadcast stream. Re-initializing this
  /// service (e.g. re-login on the same app instance) without ever properly
  /// detaching the old listener stacked a second `onMessage` handler, which
  /// showed every foreground push as two duplicate local notifications.
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _backgroundTapSub;

  /// The most recently registered FCM token, kept so [unregisterToken] on
  /// sign-out can tell the backend exactly which token to remove without a
  /// second `getToken()` round trip (which can also legitimately return a
  /// different token than the one currently registered, if it rotated
  /// between register and unregister).
  String? _registeredToken;

  /// Set by [ZendAppModel] (via [DmThreadScreen]/[MissionRoom] mounting) so
  /// foreground chat notifications can be suppressed for whichever thread
  /// the user is actively looking at — receiving a status-bar/local
  /// notification for the exact conversation on screen is jarring and was
  /// previously unconditional.
  static String? activeDmRoomId;
  static String? activePoolId;

  PushNotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _requestPermissions();
    await _registerToken();
    _listenForTokenRefresh();
    _listenForForegroundMessages();
    _listenForBackgroundNotificationTaps();
    // Note: getInitialMessage (terminated-state tap) is handled in main.dart
    // before runApp — not here — to avoid the race between post-auth
    // initialize() and app.dart's initState postFrameCallback.
  }

  void dispose() {
    _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _backgroundTapSub?.cancel();
    _backgroundTapSub = null;
  }

  /// Unregisters this device's FCM token from the backend and clears any
  /// local notification state that belongs to the outgoing session. Call
  /// this from the sign-out flow, before [ZendAppModel.resetState] tears
  /// down the rest of the session — otherwise a signed-out device keeps
  /// receiving the just-signed-out account's pushes until FCM happens to
  /// report the token as stale on some future send.
  Future<void> unregisterToken() async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      await _apiClient.unregisterFcmToken(token);
    } catch (e) {
      // Non-fatal — the backend will eventually clean up the token
      // reactively when FCM reports it as unregistered/invalid for the old
      // account. Signing out proceeds regardless.
      if (kDebugMode) {
        debugPrint('PushNotifications: failed to unregister token: $e');
      }
    } finally {
      _registeredToken = null;
      await clearBadge();
    }
  }

  /// Clears the iOS home-screen badge count. Call on resume/foreground and
  /// after sign-out — the badge is otherwise never cleared client-side, so
  /// it can sit indefinitely at a stale count even after the user has read
  /// everything (or signed out entirely).
  Future<void> clearBadge() async {
    final darwinImpl = _localNotifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    // badgeNumber: 0 clears the badge; flutter_local_notifications' iOS
    // implementation applies this via a zero-duration local notification
    // under the hood, which is the supported way to change the badge
    // outside of an actual push payload.
    await darwinImpl?.show(
      _kBadgeClearNotificationId,
      null,
      null,
      notificationDetails: const DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: true,
        presentSound: false,
        badgeNumber: 0,
      ),
    );
    await darwinImpl?.cancel(_kBadgeClearNotificationId);
  }

  /// Reserved ID for the zero-duration "clear badge" notification — never
  /// visible to the user (presentAlert/presentSound are both false) and
  /// immediately cancelled after use, so it can't collide with any category
  /// range in [_notificationIdFor].
  static const _kBadgeClearNotificationId = -1;

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // One Android channel per category, matching the backend's
    // NotificationCategory::android_channel_id() exactly (see
    // src/push_notifications.rs and notification_category.dart). Previously
    // every notification — DMs, pool chat, activity reactions, savings
    // progress, and actual money transfers — shared a single
    // "zend_transfers" channel, so muting any one of them via Android's own
    // per-channel notification settings silently muted all of them.
    for (final category in NotificationCategoryKind.values) {
      await androidImpl?.createNotificationChannel(
        AndroidNotificationChannel(
          category.androidChannelId,
          category.androidChannelName,
          description: category.androidChannelDescription,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }

    // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+).
    // Without this grant, notifications will not appear in the status bar
    // even if FCM delivers them successfully.
    await androidImpl?.requestNotificationsPermission();
  }

  Future<void> _requestPermissions() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (kDebugMode) {
      debugPrint(
        'PushNotifications: permission status = ${settings.authorizationStatus}',
      );
    }
  }
  Future<void> _registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _sendTokenToBackend(token);
    }
  }

  void _listenForTokenRefresh() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _sendTokenToBackend(newToken);
    });
  }

  /// Handles notification taps when the app was backgrounded (not killed).
  /// When the app is killed, [getInitialMessage] handles it — call that
  /// from main() or initState of your root widget.
  void _listenForBackgroundNotificationTaps() {
    // App was in background and user tapped the notification
    _backgroundTapSub?.cancel();
    _backgroundTapSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationData(message.data);
    });
  }

  /// Called when a new pool message notification arrives (foreground or tap).
  /// Registered by [ZendAppModel] to mark the pool as having unread messages.
  static void Function(String poolId)? onPoolMessageReceived;

  void _handleNotificationData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';

    // Legacy: payment_request keeps its own static field because app.dart's
    // existing _handlePaymentRequestNotification path uses it directly — we
    // keep it working while also storing the typed destination below.
    if (type == 'payment_request') {
      try {
        final notification = PaymentRequestNotification.fromJson(data);
        if (notification.requesterZendtag.isNotEmpty && notification.amountUsdc > 0) {
          pendingPaymentRequestFromNotification = notification;
        }
      } catch (_) {}
      // payment_request is handled by the existing path — don't also store
      // a NotifActivityFeed destination that would duplicate the navigation.
      return;
    }

    // drop_confirmed: do NOT store in pendingDropConfirmedFromNotification.
    // The receiver sheet is shown exclusively via the SSE dropConfirmed event
    // (which fires through ZendAppModel._dropConfirmedController). Using the
    // push notification as a second trigger causes the sheet to appear twice
    // because the reconciler sends both an SSE event AND a push ~45s apart.
    // The SSE path already has dedup via _shownDropTransferIds in app.dart;
    // the push path just navigates to the activity feed (handled below).

    // Parse and store a typed navigation destination for all types.
    // app.dart consumes this after unlock/authentication.
    final destination = NotificationDestination.fromData(data);
    PendingNotificationService.store(destination);

    // Pool message badge — mark pool as having new messages
    if (type == 'pool_message') {
      final poolId = data['pool_id'] as String?;
      if (poolId != null) {
        onPoolMessageReceived?.call(poolId);
      }
    }
  }

  void _listenForForegroundMessages() {
    _foregroundMessageSub?.cancel();
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // With 'notification' field in the FCM payload, the system bar shows
      // the notification automatically when the app is backgrounded.
      // When the app is FOREGROUND, Android suppresses the system notification
      // so we show a local one here — but only for messages the user needs to see.
      final title = message.data['title'] as String? ??
          message.notification?.title ??
          'Zend';
      final body = message.data['body'] as String? ??
          message.notification?.body ??
          '';
      final type = message.data['type'] as String? ?? '';

      if (body.isEmpty) return;

      // Don't show foreground notification for drop_confirmed on the sender's side
      // — they're already seeing the success animation in the Drop sheet.
      // Do show it for the receiver (role = 'receiver') and all other types.
      final role = message.data['role'] as String? ?? '';
      if (type == 'drop_confirmed' && role == 'sender') return;

      // Route-aware suppression: don't pop a local notification for the
      // exact DM thread or pool chat the user is already looking at. This
      // previously fired unconditionally — receiving a status-bar
      // notification for the message you're actively reading on screen is
      // the single most jarring case of a notification "lying" about
      // needing your attention.
      if (type == 'dm_message') {
        final roomId = message.data['room_id'] as String?;
        if (roomId != null && roomId == activeDmRoomId) return;
      }
      if (type == 'pool_message') {
        final poolId = message.data['pool_id'] as String?;
        if (poolId != null && poolId == activePoolId) return;
      }

      final category = NotificationCategoryKindX.fromType(type);

      _localNotifications.show(
        _notificationIdFor(message.data, type),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            category.androidChannelId,
            category.androidChannelName,
            channelDescription: category.androidChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            styleInformation: BigTextStyleInformation(body, contentTitle: title),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );

      // Pool message badge — mark pool as having new messages. Previously
      // only wired from the background-tap/terminated path via
      // _handleNotificationData; a foreground pool message never updated the
      // badge at all, since this method never called it.
      if (type == 'pool_message') {
        final poolId = message.data['pool_id'] as String?;
        if (poolId != null) onPoolMessageReceived?.call(poolId);
      }
    });
  }

  /// Derives a stable local-notification ID from the notification's own
  /// identity (a room/edge/transfer/pool ID from its data payload), falling
  /// back to a hash of the title+body only if no such ID is present.
  ///
  /// The previous implementation used `message.hashCode` — Dart's default
  /// `Object.hashCode`, which is only guaranteed consistent for the
  /// lifetime of that single `RemoteMessage` instance and has no
  /// relationship to the notification's actual content. Two independent
  /// deliveries of "logically the same" notification (e.g. a duplicate FCM
  /// delivery, or the same DM room notified twice in quick succession)
  /// could get different IDs and stack as separate status-bar entries
  /// instead of one being replaced/updated by the other; conversely two
  /// unrelated notifications could collide on the same ID by coincidence.
  /// A content-derived ID makes "the same underlying thing" collapse to one
  /// notification slot deterministically.
  int _notificationIdFor(Map<String, dynamic> data, String type) {
    final identity = data['room_id'] as String? ??
        data['pool_id'] as String? ??
        data['edge_id'] as String? ??
        data['transfer_id'] as String? ??
        '$type:${data['title']}:${data['body']}';
    return identity.hashCode & 0x7fffffff; // keep it a positive 32-bit int
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _apiClient.registerFcmToken(token);
      _registeredToken = token;
      if (kDebugMode) {
        debugPrint('PushNotifications: FCM token registered with backend');
      }
    } catch (e) {
      // Non-fatal — token will be re-registered on next app launch
      if (kDebugMode) {
        debugPrint('PushNotifications: failed to register token: $e');
      }
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationData(data);
    } catch (_) {}
  }

  /// Consume and return the pending payment request notification from a tap.
  static PaymentRequestNotification? consumePendingPaymentRequest() {
    final pending = pendingPaymentRequestFromNotification;
    pendingPaymentRequestFromNotification = null;
    return pending;
  }
}

/// Top-level handler for background/terminated FCM messages.
/// Must be a top-level function (not a class method) — Flutter requirement.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kDebugMode) {
    debugPrint('PushNotifications: background message received: ${message.messageId}');
  }
}
