import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceId {
  static const _ch = MethodChannel('app.device.id');
  static const _storage = FlutterSecureStorage(); // iOS=Keychain, Android=Keystore 기반

  static Future<String> get() async {
    if (Platform.isAndroid) {
      final ssaid = await _ch.invokeMethod<String>('getAndroidId');
      if (ssaid != null && ssaid.isNotEmpty) return ssaid;
      return _fallbackUuid(); // 드문 예외 케이스 방어
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
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(h).join();
    return '${b.substring(0,8)}-${b.substring(8,12)}-${b.substring(12,16)}-${b.substring(16,20)}-${b.substring(20)}';
  }
}
