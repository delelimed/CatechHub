import 'package:flutter/material.dart';

class EventTrackingService {
  static bool _isEnabled = false;

  static void init(bool analyticsConsent) {
    _isEnabled = analyticsConsent;
  }

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static void trackEvent(String eventName, {Map<String, dynamic>? data}) {
    if (!_isEnabled) return;

    // Log per debug
    debugPrint('📊 Event tracked: $eventName ${data ?? ''}');
  }

  static void trackPageView(String pageName) {
    trackEvent('page_view', data: {'page': pageName});
  }

  static void trackAction(String actionName, {String? category}) {
    trackEvent('action', data: {
      'action': actionName,
      'category': category,
    });
  }

  static void trackError(String errorName, {String? message}) {
    trackEvent('error', data: {
      'error': errorName,
      'message': message,
    });
  }
}
