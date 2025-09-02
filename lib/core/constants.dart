import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String kBaseHost = 'demo.guard-force.net';
final Uri kLoginUri = Uri.parse('https://$kBaseHost/login');

const String kActionStopAlarm = 'STOP_ALARM';
const String kMethodChannelAlarm = 'gf_alarm_channel';
const String kMethodChannelDeviceId = 'app.device.id';

// 알림 채널 정의
const AndroidNotificationChannel criticalChannel = AndroidNotificationChannel(
  'alarm_channel_v4',
  'Critical Alerts',
  description: '무음/방해금지에도 울릴 수 있는 긴급 알림',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('critical_alert'),
  enableVibration: true,
  showBadge: true,
  audioAttributesUsage: AudioAttributesUsage.alarm,
);

const AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
  'normal_channel_v1',
  'General Alerts',
  description: '일반 알림(무음/방해금지를 우회하지 않음)',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);
