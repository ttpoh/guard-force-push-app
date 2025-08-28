import UIKit
import Flutter
import UserNotifications

import FirebaseCore      // FirebaseApp
import FirebaseMessaging // Messaging, MessagingDelegate

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate { // ⬅️ UNUserNotificationCenterDelegate 표기는 제거
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // FlutterAppDelegate가 이미 UNUserNotificationCenterDelegate를 채택하고 있으므로 delegate 지정만 하면 됩니다.
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    application.registerForRemoteNotifications()

    // Flutter 부트스트랩
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs 토큰 연결
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // ✅ 포그라운드 표시(배너/리스트/사운드/배지) — 반드시 override
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge]) // iOS 13 이하
    }
  }

  // 알림 탭 처리(선택) — 반드시 override
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  // ✅ 최신 FirebaseMessaging 콜백: FCM 등록 토큰 갱신
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("FCM registration token: \(fcmToken ?? "-")")
    // 필요하면 토큰을 네이티브 → Flutter로 전달하거나 서버에 동기화
  }

  // (참고) 데이터 메시지 전용 콜백은 iOS에선 별도 지원이 제한적입니다.
  // 백그라운드 데이터 처리는 아래 메서드로 받습니다(필요 시 주석 해제).
  /*
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    print("Remote data: \(userInfo)")
    completionHandler(.newData)
  }
  */
}
