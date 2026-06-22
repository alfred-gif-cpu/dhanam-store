import 'dart:io';

class AppConfig {
  static String get baseUrl {
    // Use emulator localhost on Android emulator, production URL otherwise
    const prodUrl = String.fromEnvironment('API_URL', defaultValue: '');
    if (prodUrl.isNotEmpty) return prodUrl;

    // Android emulator uses 10.0.2.2 to reach host machine
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }
}
