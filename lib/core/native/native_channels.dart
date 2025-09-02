import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants.dart';

class NativeAlarm {
  static const MethodChannel _ch = MethodChannel(kMethodChannelAlarm);

  static Future<void> startAlarmSound({required bool loop}) async {
    try {
      await _ch.invokeMethod('startAlarmSound', {'loop': loop});
    } catch (e) {
      debugPrint('startAlarmSound error: $e');
    }
  }

  static Future<void> stopAlarmSound() async {
    try {
      await _ch.invokeMethod('stopAlarmSound');
    } catch (e) {
      debugPrint('stopAlarmSound error: $e');
    }
  }
}
