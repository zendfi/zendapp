import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../models/notification_destination.dart';
import '../models/payment_request_notification.dart';
import 'api_client.dart';
import 'pending_notification_service.dart';

class PushNotificationService {
  final ApiClient _apiClient;

  static const _androidChannelId = 'zend_transfers';
  static const _androidChannelName = 'Zend Transfers';
  static const _androidChannelDesc = 'Notifications for incoming Zend transfers';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Pending payment request from a notification tap (background/terminated).
  /// Consumed once by the app after session restore.
  static PaymentRequestNotification? pendingPaymentRequestFromNotification;

  /// Pending drop confirmation from a push notification (background/terminated).
  /// Consumed by the app on resume to trigger haptics + overlay.
  static Map<String, dynamic>? pendingDropConfirmedFromNotification;

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
    FirebaseMessaging.onMessage.drain<RemoteMessage>();
  }

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

    const channel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDesc,
      importance: Importance.high,
      playSound: true,
    );

    final androidImpl = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImpl?.createNotificationChannel(channel);

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
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _sendTokenToBackend(newToken);
    });
  }

  /// Handles notification taps when the app was backgrounded (not killed).
  /// When the app is killed, [getInitialMessage] handles it — call that
  /// from main() or initState of your root widget.
  void _listenForBackgroundNotificationTaps() {
    // App was in background and user tapped the notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
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

    // drop_confirmed keeps its own field for the haptics/overlay path.
    if (type == 'drop_confirmed') {
      pendingDropConfirmedFromNotification = data;
    }

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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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

      _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await _apiClient.registerFcmToken(token);
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

  /// Consume and return the pending drop confirmation from a background push.
  static Map<String, dynamic>? consumePendingDropConfirmed() {
    final pending = pendingDropConfirmedFromNotification;
    pendingDropConfirmedFromNotification = null;
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
