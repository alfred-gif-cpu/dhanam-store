import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
  static const _apiUrl = String.fromEnvironment('API_URL', defaultValue: '');

  /// Where the app talks to the backend.
  ///
  /// `API_URL` is a compile-time constant and has to be passed at build time:
  ///
  ///   flutter build apk --release --dart-define=API_URL=https://…
  ///
  /// Forget it and a *release* build used to fall back to the local dev server
  /// silently — a signed APK that reaches 10.0.2.2:8000, an address that only
  /// means anything on an emulator running on the developer's own machine. On
  /// a real phone every screen just times out. There was an `assert` here that
  /// looked like it guarded this, but it asserted `true` and its message could
  /// never print; asserts are stripped from release builds anyway.
  ///
  /// So release builds now refuse to start rather than pointing at a laptop.
  /// Debug and profile builds keep the fallback, which is what makes
  /// `flutter run` work with no arguments.
  static String get baseUrl {
    if (_apiUrl.isNotEmpty) return _apiUrl;

    if (kReleaseMode) {
      throw StateError(
        'API_URL was not set at build time. This release build would otherwise '
        'talk to a local development server and fail on every device. Rebuild '
        'with: flutter build apk --release --dart-define=API_URL=https://…',
      );
    }

    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {}
    return 'http://localhost:8000';
  }

  static bool get isProduction => _apiUrl.isNotEmpty;
}
