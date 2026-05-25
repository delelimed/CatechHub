import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';

class AnalyticsService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static PackageInfo? _packageInfo;

  static Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      Map<String, dynamic> deviceData = {
        'timestamp': DateTime.now().toIso8601String(),
        'app_version': _packageInfo?.version ?? 'unknown',
        'platform': Platform.isAndroid ? 'android' : 'ios',
      };

      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceData.addAll({
          'device_model': androidInfo.model,
          'device_manufacturer': androidInfo.manufacturer,
          'android_version': androidInfo.version.release,
          'device_id': androidInfo.id,
        });
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceData.addAll({
          'device_model': iosInfo.model,
          'ios_version': iosInfo.systemVersion,
          'device_id': iosInfo.identifierForVendor,
        });
      }

      return deviceData;
    } catch (e) {
      debugPrint('Errore nel recupero info dispositivo: $e');
      return {'error': 'Impossibile recuperare info dispositivo'};
    }
  }

  static Map<String, dynamic> formatDeviceInfoForFeedback(
    Map<String, dynamic> deviceInfo,
  ) {
    return {
      'Dispositivo': deviceInfo['device_model'] ?? 'Unknown',
      'Produttore': deviceInfo['device_manufacturer'] ?? 'N/A',
      'SO': Platform.isAndroid
          ? 'Android ${deviceInfo['android_version']}'
          : 'iOS ${deviceInfo['ios_version']}',
      'Versione App': deviceInfo['app_version'] ?? 'Unknown',
      'Data': deviceInfo['timestamp'] ?? DateTime.now().toString(),
    };
  }
}
