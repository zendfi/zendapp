import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';

/// Handles FCM token registration, permission requests, and foreground
/// notification display for ZendApp.
///
/// Architecture:
/// - Background/terminated messages are handled by [firebaseMessagingBackgroundHandler]
///   (top-level function, registered before runApp)
/// - Foreground messages are shown as local notifications via flutter_local_notifications
/// - FCM token is registered with the backend on login and refreshed automatically
class PushNotificationService {
  final ApiClient _apiClient;

  static const _androidChannelId = 'zend_transfers';
  static const _androidChannelName = 'Zend Transfers';
  static const _androidChannelDesc = 'Notifications for incoming Zend transfers';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  PushNotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// Initialize Firebase, request permissions, set up notification channels,
  /// and register the FCM token with the backend.
  ///
  /// Call this once after the user is authenticated.
  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _requestPermissions();
    await _registerToken();
    _listenForTokenRefresh();
    _listenForForegroundMessages();
  }

  /// Stop listening for notifications (call on logout).
  void dispose() {
    FirebaseMessaging.onMessage.drain<RemoteMessage>();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

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

    // Create the Android notification channel
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
      final notification = message.notification;
      if (notification == null) return;

      // Show as a local notification while the app is in the foreground
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
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
  // Firebase must be initialized before any Firebase calls in background isolate
  await Firebase.initializeApp();
  if (kDebugMode) {
    debugPrint('PushNotifications: background message received: ${message.messageId}');
  }
  // Background messages with a notification payload are shown automatically by FCM.
  // Data-only messages can be processed here if needed.
}
