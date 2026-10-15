import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Posts system notifications, so a file, clipboard item, message or pairing
/// request that arrives while Nearlink is not in the foreground is visible
/// rather than silent.
///
/// Every call is wrapped: notifications are a nicety, and a platform that
/// refuses them must never take the app down.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static int _nextId = 1;

  static const String _channelId = 'nearlink_receive';
  static const String _channelName = 'Nearlink';
  static const String _channelDescription =
      'Files, clipboard text and messages received from your devices';

  /// The small status-bar icon, generated alongside the app icon.
  static const String _androidIcon = 'ic_stat_nearlink';

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open Nearlink'),
      );
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (_) {
      // Not available here; carry on without it.
    }
  }

  /// Ask the OS for permission to post notifications. Safe to call more than
  /// once — the platform ignores repeat requests.
  static Future<void> requestPermission() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _androidIcon,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }
}
