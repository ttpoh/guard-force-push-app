import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../constants.dart';
import '../native/native_channels.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initLocalNotifications() async {
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) {
      if (resp.actionId == kActionStopAlarm) NativeAlarm.stopAlarmSound();
    },
    onDidReceiveBackgroundNotificationResponse:
        notificationActionBackgroundHandler,
  );

  await ensureChannels();
}

Future<void> ensureChannels() async {
  final androidImpl = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  final channels =
      await androidImpl?.getNotificationChannels() ?? <AndroidNotificationChannel>[];

  if (!channels.any((c) => c.id == criticalChannel.id)) {
    await androidImpl?.createNotificationChannel(criticalChannel);
  }
  if (!channels.any((c) => c.id == normalChannel.id)) {
    await androidImpl?.createNotificationChannel(normalChannel);
  }
}

@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse response) {
  if (response.actionId == kActionStopAlarm) NativeAlarm.stopAlarmSound();
}

Future<void> showLocalNotification({
  required String title,
  required String body,
  required bool critical,
  Map<String, dynamic>? payload,
  String? iosSound,
}) async {
  final actions = <AndroidNotificationAction>[
    if (critical)
      const AndroidNotificationAction(
        kActionStopAlarm,
        '중지',
        showsUserInterface: false,
        cancelNotification: true,
      ),
  ];

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        critical ? criticalChannel.id : normalChannel.id,
        critical ? criticalChannel.name : normalChannel.name,
        channelDescription:
            critical ? criticalChannel.description : normalChannel.description,
        importance: critical ? Importance.max : Importance.high,
        priority: critical ? Priority.high : Priority.defaultPriority,
        category: critical
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.message,
        playSound: !critical, // 긴급은 네이티브 서비스 쪽에서 사운드 재생
        audioAttributesUsage:
            critical ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        fullScreenIntent: false,
        icon: '@mipmap/ic_launcher',
        actions: actions,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: iosSound ?? (critical ? 'critical_alert.caf' : null),
        interruptionLevel:
            critical ? InterruptionLevel.critical : InterruptionLevel.active,
      ),
    ),
    payload: payload == null ? null : jsonEncode(payload),
  );
}
