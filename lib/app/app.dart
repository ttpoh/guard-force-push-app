import 'package:flutter/material.dart';
import '../features/webview/webview_page.dart';
import '../core/settings/alarm_settings.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.initialSettings});
  final AlarmSettings initialSettings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(initialSettings: initialSettings),
    );
  }
}
