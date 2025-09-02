import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase_options.dart';
import '../core/notifications/local_notifications.dart';
import '../core/push/fcm_service.dart';
import '../core/settings/alarm_settings.dart';

class BootstrapResult {
  final AlarmSettings settings;
  BootstrapResult(this.settings);
}

Future<BootstrapResult> bootstrap() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 알림 권한
  await Permission.notification.request();

  // 로컬 알림 초기화 & 채널 보장
  await initLocalNotifications();

  // iOS critical alert 권한 포함
  await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true, criticalAlert: true,
  );

  // 앱 설정 로드 및 FCM 수신 핸들러 연결
  final settings = await AlarmSettings.load();
  attachForegroundHandler(settings);

  return BootstrapResult(settings);
}
