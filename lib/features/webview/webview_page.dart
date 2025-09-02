import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants.dart';
import '../../core/device/device_id.dart';
import '../../core/settings/alarm_settings.dart';

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

  // 설정 상태(하단 설정 시 저장)
  late bool _normalOn;
  late bool _criticalOn;
  late bool _criticalUntilStopped;

  // 로그인 이후(호스트=베이스, path != /login) 하단바 표시
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

    // FCM 토큰 갱신 시 쿠키/LS 반영 + 서버 sync
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      await _setPushTokenCookies(t);
      if (_isGuardForceUrl(_lastUrl)) await _callSyncInPage();
    });

    _injectTokenAndLoad();
  }

  bool _isGuardForceUrl(String url) {
    try {
      return Uri.parse(url).host == kBaseHost;
    } catch (_) {
      return false;
    }
  }

  // 쿠키/로컬스토리지 주입
  Future<void> _setPushTokenCookies(String token) async {
    await _cookieManager.setCookie(const WebViewCookie(
      name: 'cookie_placeholder',
      value: '1',
      domain: kBaseHost,
      path: '/',
    ));

    await _cookieManager.setCookie(WebViewCookie(
      name: 'push_token',
      value: token,
      domain: kBaseHost,
      path: '/',
    ));
    
    debugPrint('[WebView] setCookie push_token=$token');

    final os = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    await _cookieManager.setCookie(WebViewCookie(
      name: 'os',
      value: os,
      domain: kBaseHost,
      path: '/',
    ));

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

    await _controller.runJavaScript(
      'window.localStorage.setItem("fcm_token", "$token");',
    );
  }

  // 로그인 세션 유지 상태에서 서버에 토큰/디바이스 동기화
  Future<void> _callSyncInPage() async {
    try {
      await _controller.runJavaScript(r'''
        fetch("/api/fcm/sync", {
          method: "POST",
          headers: {
            "X-FCM-Token": window.localStorage.getItem("fcm_token"),
            "X-Device-Id": window.localStorage.getItem("device_id")
          },
          credentials: "include"
        }).then(res => res.text()).catch(()=>{});
      ''');
    } catch (e) {
      // 웹뷰 JS 에러는 조용히 로깅만
      debugPrint('sync failed: $e');
    }
  }

  // 초기 로드 전 device_id 선주입 + FCM 토큰 쿠키화
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
  // 설정 저장
  // --------------------------
  Future<void> _persistSettings() async {
    final s = AlarmSettings(
      normalOn: _normalOn,
      criticalOn: _criticalOn,
      criticalUntilStopped: _criticalUntilStopped,
    );
    await s.save();
  }

  // --------------------------
  // 알림 설정 화면(안드로이드)
  // --------------------------
  Future<void> _openAppNotificationSettings() async {
    if (!Platform.isAndroid) return;
    final pkg = (await PackageInfo.fromPlatform()).packageName;
    final intent = AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{'android.provider.extra.APP_PACKAGE': pkg},
    );
    await intent.launch();
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
                subtitle: const Text('필요 시 방해금지 모드도 우회'),
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
            const Expanded(
              child: Center(
                child: Text(
                  'GuardForce',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
