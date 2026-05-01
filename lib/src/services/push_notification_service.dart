import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import 'api_client.dart';

class PushNotificationService {
  final ApiClient _apiClient;

  static const _androidChannelId = 'zend_transfers';
  static const _androidChannelName = 'Zend Transfers';
  static const _androidChannelDesc = 'Notifications for incoming Zend transfers';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  PushNotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _requestPermissions();
    await _registerToken();
    _listenForTokenRefresh();
    _listenForForegroundMessages();
  }

  void dispose() {
    FirebaseMessaging.onMessage.drain<RemoteMessage>();
  }

  Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // We request separately
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

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
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

  void _listenForForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // We use data-only messages so onMessage fires reliably in foreground.
      // Title and body are in message.data, not message.notification.
      final title = message.data['title'] as String? ??
          message.notification?.title ??
          'Zend';
      final body = message.data['body'] as String? ??
          message.notification?.body ??
          '';

      if (body.isEmpty) return;

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
    // TODO: Navigate to the relevant screen based on payload
    // e.g., if payload contains transfer_id, navigate to activity screen
    if (kDebugMode) {
      debugPrint('PushNotifications: tapped notification payload=${response.payload}');
    }
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
