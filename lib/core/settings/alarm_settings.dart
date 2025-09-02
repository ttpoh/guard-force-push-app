import 'package:shared_preferences/shared_preferences.dart';

class AlarmSettings {
  static const _kNormalOn = 'normal_alarm_enabled';
  static const _kCriticalOn = 'critical_alarm_enabled';
  static const _kCriticalUntilStopped = 'critical_until_stopped';

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
