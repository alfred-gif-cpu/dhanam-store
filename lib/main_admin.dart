// Dhanam Admin
//
// One of three apps built from this codebase — customer, admin, delivery. They
// share every screen, model and service; only the front door differs, so there
// is nothing to keep in sync.
//
// Build:
//   flutter build apk --release --flavor admin --target lib/main_admin.dart \
//     --dart-define=API_URL=https://dhanam-store-production.up.railway.app
//
// Handed out as an APK. Not a Play Store listing.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/secure_admin_dashboard.dart';
import 'services/admin_auth_service.dart';
import 'services/notification_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AdminAuthService().load();
  await NotificationService().init();

  NotificationService().onMessageTapped = (message) {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null) return;
    if (!AdminAuthService().isLoggedIn) return;
    nav.push(MaterialPageRoute(builder: (_) => const SecureAdminDashboard()));
  };

  runApp(const DhanamAdminApp());
}

class DhanamAdminApp extends StatelessWidget {
  const DhanamAdminApp({super.key});

  /// Where a launch lands. The admin session lasts 24 hours, so most mornings
  /// this is the login screen — the right default for a shared shop phone.
  static Widget home() {
    final auth = AdminAuthService();
    if (!auth.isLoggedIn) return const AdminLoginScreen(app: StaffApp.admin);
    // A session belonging to the other app can be left behind by an install
    // over the top; send it back to a login that will reject it clearly.
    if (!auth.isOwner) return const AdminLoginScreen(app: StaffApp.admin);
    return const SecureAdminDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanam Admin',
      theme: appTheme(),
      navigatorKey: NotificationService.navigatorKey,
      // Same clamp as the customer app: these screens have fixed-width rows
      // and pill badges that clip before a phone's largest font setting.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15)),
          child: child!,
        );
      },
      home: home(),
    );
  }
}
