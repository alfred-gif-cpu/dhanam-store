import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0D47A1);
  static const primaryLight = Color(0xFF2196F3);
  static const primarySurface = Color(0xFFE3F2FD);
  static const accent = Color(0xFFFF9800);
  static const accentLight = Color(0xFFFFF3E0);
  static const surface = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF6B7280);
  static const textHint = Color(0xFF9CA3AF);
  static const divider = Color(0xFFE5E7EB);
  static const error = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);
  static const star = Color(0xFFFBBF24);
}

/// Shared motion values, so the app springs the same way everywhere.
///
/// The one rule worth stating: **overshoot curves belong on movement, never on
/// opacity.** `easeOutBack` and `elasticOut` deliberately travel past their end
/// value and come back, which is the bounce. On a transform that reads as
/// weight; on a fade it means an opacity above 1 or below 0, which Flutter
/// clamps — so the fade stalls at the ends and the animation looks broken
/// rather than lively. That is why entrances below animate their slide with
/// [entrance] while their fade stays on [fade].
class AppMotion {
  /// Entrances that slide or scale into place. Overshoots, then settles.
  static const entrance = Curves.easeOutBack;

  /// The fade half of an entrance. Never overshoots — see the class note.
  static const fade = Curves.easeOut;

  /// Tap feedback that should feel springy: a heart, a quantity, a tick.
  /// Wobbles around its end value, so it needs a little longer to settle.
  static const pop = Curves.elasticOut;

  static const entranceDuration = Duration(milliseconds: 700);
  static const popDuration = Duration(milliseconds: 450);
  static const pageDuration = Duration(milliseconds: 500);
}

ThemeData appTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.primary,
    scaffoldBackgroundColor: AppColors.surface,
    // Named "AppSans" (not "Roboto") deliberately — some Android skins
    // (MIUI etc.) intercept any font family literally named "Roboto" to
    // apply a system-wide theme font, even overriding an app's own
    // bundled asset registered under that same name. A unique family
    // name sidesteps that interception entirely.
    fontFamily: 'AppSans',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[300],
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textHint,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
