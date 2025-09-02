import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../notifications/local_notifications.dart';
import '../native/native_channels.dart';
import '../settings/alarm_settings.dart';

Future<void> handleIncoming(RemoteMessage message, AlarmSettings settings) async {
  final n = message.notification;
  final data = message.data;
  final title = n?.title ?? data['title'] ?? '알림';
  final body  = n?.body  ?? data['body']  ?? '';

  String? iosSound;
  if (data['ios_config'] != null) {
    try {
      final iosConfig = jsonDecode(data['ios_config']) as Map<String, dynamic>;
      iosSound = iosConfig['sound'] as String?;
    } catch (_) {}
  }

  if (Platform.isAndroid) {
    if (settings.criticalOn) {
      await NativeAlarm.startAlarmSound(loop: settings.criticalUntilStopped);
      await showLocalNotification(
        title: title,
        body: body,
        critical: true,
        payload: data.isNotEmpty ? data : null,
        iosSound: iosSound,
      );
      return;
    }
    if (settings.normalOn) {
      await showLocalNotification(
        title: title,
        body: body,
        critical: false,
        payload: data.isNotEmpty ? data : null,
        iosSound: iosSound,
      );
      return;
    }
    // 둘 다 OFF → 무시
    return;
  }

  // iOS
  await showLocalNotification(
    title: title,
    body: body,
    critical: settings.criticalOn,
    payload: data.isNotEmpty ? data : null,
    iosSound: iosSound,
  );
}

void attachForegroundHandler(AlarmSettings settings) {
  FirebaseMessaging.onMessage.listen((m) => handleIncoming(m, settings));
}
