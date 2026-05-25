import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_database.dart';

final analyticsConsentProvider = StateNotifierProvider<AnalyticsConsentNotifier, bool>(
  (ref) => AnalyticsConsentNotifier(),
);

class AnalyticsConsentNotifier extends StateNotifier<bool> {
  AnalyticsConsentNotifier() : super(_loadConsentFromStorage());

  static bool _loadConsentFromStorage() {
    final box = LocalDatabase.auth();
    return box.get('analytics_consent', defaultValue: false);
  }

  Future<void> setConsent(bool value) async {
    final box = LocalDatabase.auth();
    await box.put('analytics_consent', value);
    state = value;
  }

  bool get hasConsented => state;
}
