import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await NotificationService().showNotification(message);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final String _baseUrl = AppConfig.baseUrl;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  Function(RemoteMessage)? onMessageTapped;

  static const _androidChannel = AndroidNotificationChannel(
    'dhanam_orders',
    'Order Updates',
    description: 'Notifications for order status updates and promotions',
    importance: Importance.high,
  );

  Future<void> init() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Auth status: ${settings.authorizationStatus}');

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);

    _fcmToken = await _fcm.getToken();
    debugPrint('[FCM] Token: $_fcmToken');

    _fcm.onTokenRefresh.listen((token) {
      _fcmToken = token;
      _registerToken(token);
    });

    if (_fcmToken != null) {
      _registerToken(_fcmToken!);
    }

    FirebaseMessaging.onMessage.listen(_handleForeground);
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _handleMessageTap(initial);
    }
  }

  void _handleForeground(RemoteMessage message) {
    showNotification(message);
  }

  void _handleMessageTap(RemoteMessage message) {
    onMessageTapped?.call(message);
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        final message = RemoteMessage(data: data);
        onMessageTapped?.call(message);
      } catch (_) {}
    }
  }

  Future<void> showNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'Dhanam Stores';
    final body = notification?.body ?? message.data['body'] ?? '';

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
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
  }

  Future<void> _registerToken(String token) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$_baseUrl/notifications/register'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'token': token}));
      await request.close();
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
  }
}
