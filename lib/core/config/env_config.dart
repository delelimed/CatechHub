import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static bool _initialized = false;

  static Future<void> load() async {
    if (_initialized) return;
    await dotenv.load(fileName: '.env');
    _initialized = true;
  }

  static String get freeraspReleaseHash =>
      dotenv.env['FREERASP_RELEASE_HASH'] ?? '';

  static String get freeraspPackageName =>
      dotenv.env['FREERASP_PACKAGE_NAME'] ?? '';

  static String get wiredashProjectId =>
      dotenv.env['WIREDASH_PROJECT_ID'] ?? '';

  static String get wiredashApiSecret =>
      dotenv.env['WIREDASH_API_SECRET'] ?? '';
}