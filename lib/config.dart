import 'dart:io';

class AppConfig {
  static const _apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  static String get baseUrl {
    if (_apiUrl.isNotEmpty) return _apiUrl;

    assert(() {
      return true;
    }(), 'API_URL not set — falling back to local dev server');

    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }

  static bool get isProduction => _apiUrl.isNotEmpty;
}
