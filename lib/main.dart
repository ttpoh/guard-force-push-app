import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // ★ 추가: UUID용

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // ★ 추가: Keychain/Keystore
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'firebase_options.dart';

/// ─────────────────────────────────────────────────────────────────
/// ★ 공통 DeviceId 헬퍼 (Android: SSAID, iOS: Keychain UUID)
/// ─────────────────────────────────────────────────────────────────
class DeviceId {
  static const _ch = MethodChannel('app.device.id'); // Android-side channel
  static const _storage = FlutterSecureStorage();    // iOS=Keychain, Android=Keystore

  static Future<String> get() async {
    if (Platform.isAndroid) {
      final ssaid = await _ch.invokeMethod<String>('getAndroidId');
      if (ssaid != null && ssaid.isNotEmpty) return ssaid;
      return _fallbackUuid(); // 드문 케이스 방어
    } else if (Platform.isIOS) {
      final existing = await _storage.read(key: 'device_uuid');
      if (existing != null && existing.isNotEmpty) return existing;

      final newId = _randomUuidV4();
      await _storage.write(
        key: 'device_uuid',
        value: newId,
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.unlocked,
        ),
      );
      return newId;
    } else {
      return _fallbackUuid();
    }
  }

  static Future<String> _fallbackUuid() async {
    final existing = await _storage.read(key: 'fallback_uuid');
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomUuidV4();
    await _storage.write(key: 'fallback_uuid', value: id);
    return id;
  }

  static String _randomUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(h).join();
    return '${b.substring(0,8)}-${b.substring(8,12)}-${b.substring(12,16)}-${b.substring(16,20)}-${b.substring(20)}';
  }
}

// ------------------------------
// 채널 정의
// ------------------------------
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

// 일반 알람(무음/방해금지 미우회)
const AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
  'normal_channel_v1',
  'General Alerts',
  description: '일반 알림(무음/방해금지를 우회하지 않음)',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  showBadge: true,
  // audioAttributesUsage 생략 → 기본값(알림)
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 네이티브(포그라운드 서비스/활동) 제어 채널
const MethodChannel _alarmCh = MethodChannel('gf_alarm_channel');

const String kActionStopAlarm = 'STOP_ALARM';

const String kBaseHost = 'demo.guard-force.net';
final Uri kLoginUri = Uri.parse('https://$kBaseHost/login');

// ------------------------------
// 앱 설정 (SharedPreferences)
// ------------------------------
class AlarmSettings {
  static const _kNormalOn = 'normal_alarm_enabled';
  static const _kCriticalOn = 'critical_alarm_enabled';
  static const _kCriticalUntilStopped = 'critical_until_stopped'; // true: 끌때까지

  bool normalOn;
  bool criticalOn;
  bool criticalUntilStopped;

  AlarmSettings({
    required this.normalOn,
    required this.criticalOn,
    required this.criticalUntilStopped,
  });

  static Future<AlarmSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AlarmSettings(
      normalOn: p.getBool(_kNormalOn) ?? true,
      criticalOn: p.getBool(_kCriticalOn) ?? true,
      criticalUntilStopped: p.getBool(_kCriticalUntilStopped) ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kNormalOn, normalOn);
    await p.setBool(_kCriticalOn, criticalOn);
    await p.setBool(_kCriticalUntilStopped, criticalUntilStopped);
  }
}

// ------------------------------
// 알림 콜백
// ------------------------------
@pragma('vm:entry-point')
void notificationActionBackgroundHandler(NotificationResponse response) {
  if (response.actionId == kActionStopAlarm) {
    const MethodChannel ch = MethodChannel('gf_alarm_channel');
    ch.invokeMethod('stopAlarmSound'); // 네이티브 알람 정지
  }
}

Future<void> _stopAlarmSoundAndroid() async {
  if (!Platform.isAndroid) return;
  try {
    await _alarmCh.invokeMethod('stopAlarmSound');
  } catch (e) {
    debugPrint('stopAlarmSound error: $e');
  }
}

Future<String> _packageName() async {
  final info = await PackageInfo.fromPlatform();
  return info.packageName;
}

Future<void> _ensureChannels() async {
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

Future<void> _openAppNotificationSettings() async {
  if (!Platform.isAndroid) return;
  final pkg = await _packageName();
  final intent = AndroidIntent(
    action: 'android.settings.APP_NOTIFICATION_SETTINGS',
    arguments: <String, dynamic>{'android.provider.extra.APP_PACKAGE': pkg},
  );
  await intent.launch();
}

Future<void> _openChannelSettings(String channelId) async {
  if (!Platform.isAndroid) return;
  final pkg = await _packageName();
  final intent = AndroidIntent(
    action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
    arguments: <String, dynamic>{
      'android.provider.extra.APP_PACKAGE': pkg,
      'android.provider.extra.CHANNEL_ID': channelId,
    },
  );
  await intent.launch();
}

// ------------------------------
// 표시용 로컬 알림
// ------------------------------
Future<void> _showLocalNotification({
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
        category:
            critical ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.message,
        // Android 사운드는:
        // - 긴급: 네이티브가 재생하므로 여기서는 꺼둠
        // - 일반: 채널 기본 소리 사용
        playSound: !critical,
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
        interruptionLevel: critical
            ? InterruptionLevel.critical
            : InterruptionLevel.active,
      ),
    ),
    payload: payload == null ? null : jsonEncode(payload),
  );
}

// ------------------------------
// 수신 처리(앱 정책 반영)
// ------------------------------
Future<void> _handleIncoming(RemoteMessage message, AlarmSettings settings) async {
  final n = message.notification;
  final data = message.data;
  final title = n?.title ?? data['title'] ?? '알림';
  final body = n?.body ?? data['body'] ?? '';

  // iOS sound 힌트(옵션)
  String? iosSound;
  if (data['ios_config'] != null) {
    try {
      final iosConfig = jsonDecode(data['ios_config']) as Map<String, dynamic>;
      iosSound = iosConfig['sound'] as String?;
    } catch (_) {}
  }

  if (Platform.isAndroid) {
    if (settings.criticalOn) {
      // 네이티브에 사운드 시작 지시 (loop 모드 전달)
      try {
        await _alarmCh.invokeMethod('startAlarmSound', {
          'loop': settings.criticalUntilStopped,
        });
      } catch (e) {
        debugPrint('startAlarmSound error: $e');
      }
      // 헤드업 알림(음소거) + STOP 액션
      await _showLocalNotification(
        title: title,
        body: body,
        critical: true,
        payload: data.isNotEmpty ? data : null,
        iosSound: iosSound,
      );
      return;
    }

    if (settings.normalOn) {
      // 일반 채널로 표시(무음/방해금지를 우회하지 않음)
      await _showLocalNotification(
        title: title,
        body: body,
        critical: false,
        payload: data.isNotEmpty ? data : null,
        iosSound: iosSound,
      );
      return;
    }

    // 둘 다 OFF → 조용히 무시(로그만)
    debugPrint('Notification suppressed by user settings (Android).');
    return;
  }

  // iOS: criticalOn이면 critical, 아니면 일반
  final useCritical = settings.criticalOn;
  await _showLocalNotification(
    title: title,
    body: body,
    critical: useCritical,
    payload: data.isNotEmpty ? data : null,
    iosSound: iosSound,
  );
}

// ------------------------------
// 앱 시작점
// ------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 권한
  await Permission.notification.request();

  // 로컬 알림 초기화
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) {
      if (resp.actionId == kActionStopAlarm) _stopAlarmSoundAndroid();
    },
    onDidReceiveBackgroundNotificationResponse: notificationActionBackgroundHandler,
  );

  // 채널 보장
  await _ensureChannels();

  // iOS critical 권한(있으면 활성)
  await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true, criticalAlert: true,
  );

  // 앱 설정 로드
  final settings = await AlarmSettings.load();

  // 포그라운드 수신 → 앱 정책대로 처리
  FirebaseMessaging.onMessage.listen((m) => _handleIncoming(m, settings));

  runApp(MyApp(initialSettings: settings));
}

// ------------------------------
// UI
// ------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.initialSettings});
  final AlarmSettings initialSettings;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WebViewPage(initialSettings: initialSettings),
      );
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key, required this.initialSettings});
  final AlarmSettings initialSettings;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  bool _isLoading = true;
  String _lastUrl = kLoginUri.toString();
  bool _didSyncOnce = false;

  // 설정 상태
  late bool _normalOn;
  late bool _criticalOn;
  late bool _criticalUntilStopped;

  bool get _shouldShowBottomBar {
    try {
      final u = Uri.parse(_lastUrl);
      return u.host == kBaseHost && u.path != '/login';
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _normalOn = widget.initialSettings.normalOn;
    _criticalOn = widget.initialSettings.criticalOn;
    _criticalUntilStopped = widget.initialSettings.criticalUntilStopped;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _lastUrl = url;
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            _lastUrl = url;
            setState(() => _isLoading = false);
            if (_isGuardForceUrl(url)) await _callSyncInPage();
          },
          onNavigationRequest: (req) {
            _lastUrl = req.url;
            setState(() {}); // 하단바 표시 조건 갱신
            return NavigationDecision.navigate;
          },
        ),
      );

    // 토큰 갱신 쿠키 반영
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _setPushTokenCookies(t);
      if (_isGuardForceUrl(_lastUrl)) await _callSyncInPage();
    });

    _injectTokenAndLoad();
  }

  bool _isGuardForceUrl(String url) {
    try {
      final host = Uri.parse(url).host;
      return host == kBaseHost;
    } catch (_) {
      return false;
    }
  }

  // ★ 수정: device_id/OS/FCM 토큰을 쿠키 & localStorage에 반영
  Future<void> _setPushTokenCookies(String token) async {
    await _cookieManager.setCookie(const WebViewCookie(
      name: 'cookie_placeholder',
      value: '1',
      domain: kBaseHost,
      path: '/',
    ));

    // FCM token
    await _cookieManager.setCookie(WebViewCookie(
      name: 'push_token',
      value: token,
      domain: kBaseHost,
      path: '/',
    ));

    // OS
    final os = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    await _cookieManager.setCookie(WebViewCookie(
      name: 'os',
      value: os,
      domain: kBaseHost,
      path: '/',
    ));

    // Device ID
    try {
      final deviceId = await DeviceId.get();
      await _cookieManager.setCookie(WebViewCookie(
        name: 'device_id',
        value: deviceId,
        domain: kBaseHost,
        path: '/',
      ));
      debugPrint('COOKIE SET: device_id=$deviceId'); // ★ 추가

      await _controller.runJavaScript(
        'try{window.localStorage.setItem("device_id","$deviceId");}catch(e){}',
      );
    } catch (_) {}

    // localStorage fcm_token
    await _controller.runJavaScript(
      'window.localStorage.setItem("fcm_token", "$token");',
    );
  }

  // ★ 수정: sync 호출 시 X-Device-Id 헤더 포함
  Future<void> _callSyncInPage() async {
    try {
      await _controller.runJavaScript('''
        fetch("/api/fcm/sync", {
          method: "POST",
          headers: {
            "X-FCM-Token": window.localStorage.getItem("fcm_token"),
            "X-Device-Id": window.localStorage.getItem("device_id")
          },
          credentials: "include"
        }).then(res => res.text());
      ''');
    } catch (e) {
      debugPrint('sync failed: $e');
    }
  }

  // ★ 수정: 페이지 로드 전에 device_id를 먼저 주입(쿠키+localStorage)
  Future<void> _injectTokenAndLoad() async {
    try {
      try {
        final deviceId = await DeviceId.get();
        await _cookieManager.setCookie(WebViewCookie(
          name: 'device_id',
          value: deviceId,
          domain: kBaseHost,
          path: '/',
        ));
        await _controller.runJavaScript(
          'try{window.localStorage.setItem("device_id","$deviceId");}catch(e){}',
        );
      } catch (_) {}

      final fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM TOKEN(getToken): $fcmToken'); // ★ 추가

      if (fcmToken != null) await _setPushTokenCookies(fcmToken);

      await _controller.loadRequest(kLoginUri);
    } catch (e) {
      debugPrint('load error: $e');
      await _controller.loadRequest(kLoginUri);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --------------------------
  // 설정 UI
  // --------------------------
  Future<void> _persistSettings() async {
    final s = AlarmSettings(
      normalOn: _normalOn,
      criticalOn: _criticalOn,
      criticalUntilStopped: _criticalUntilStopped,
    );
    await s.save();
  }

  void _openBottomMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const ListTile(
                title: Text('알림 설정', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SwitchListTile(
                title: const Text('일반 알람'),
                subtitle: const Text('무음/방해금지를 우회하지 않음'),
                value: _normalOn,
                onChanged: (v) {
                  setModal(() => _normalOn = v);
                  setState(() => _normalOn = v);
                  _persistSettings();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('긴급 알람 (무음 모드 허용)'),
                subtitle: const Text('필요 시 방해금지를 우회하여 울립니다'),
                value: _criticalOn,
                onChanged: (v) {
                  setModal(() => _criticalOn = v);
                  setState(() => _criticalOn = v);
                  _persistSettings();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IgnorePointer(
                  ignoring: !_criticalOn,
                  child: Opacity(
                    opacity: _criticalOn ? 1 : 0.5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        const Text('긴급 알람 모드'),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('1회 울림')),
                            ButtonSegment(value: true, label: Text('끌 때까지 울림')),
                          ],
                          selected: {_criticalUntilStopped},
                          onSelectionChanged: (s) {
                            final v = s.first;
                            setModal(() => _criticalUntilStopped = v);
                            setState(() => _criticalUntilStopped = v);
                            _persistSettings();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.app_settings_alt),
                title: const Text('앱 알림 설정'),
                onTap: _openAppNotificationSettings,
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2125),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: IconButton(
                tooltip: '새로고침',
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _controller.reload(),
              ),
            ),
            Expanded(
              child: Center(
                child: Image.asset(
                  'assets/icons/guardforce-logo.png',
                  height: 22,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              child: IconButton(
                tooltip: '설정',
                icon: const Icon(Icons.tune, color: Colors.white),
                onPressed: _openBottomMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _shouldShowBottomBar ? _bottomBar() : null,
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
