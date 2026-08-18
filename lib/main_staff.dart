// The staff app: same codebase, same screens, a different front door.
//
// Everything here already existed inside the customer app, reachable through a
// "Login as Staff / Owner" button on the customer login screen. That put a
// staff entrance in the lobby of a shop, and shipped 3,000 lines of admin
// screens to every customer. This entrypoint builds the same code as its own
// app instead: no second codebase, no duplicated models or services, and
// nothing to keep in sync.
//
// Build it with:
//   flutter build apk --release --flavor staff --target lib/main_staff.dart \
//     --dart-define=API_URL=https://dhanam-store-production.up.railway.app
//
// It installs alongside the customer app rather than replacing it — the staff
// flavor carries its own applicationId — so a delivery driver can also be a
// customer, and so a Play Store update to one never touches the other. It is
// distributed by handing people the APK; it is not a Play Store listing.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/admin/admin_login_screen.dart';
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/delivery_dashboard_screen.dart';
import 'screens/admin/secure_admin_dashboard.dart';
import 'services/admin_auth_service.dart';
import 'services/notification_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AdminAuthService().load();
  await NotificationService().init();

  // Same routing as the customer app used for staff notifications. Deliberately
  // not shared as a function: this app has no customer role to fall through to,
  // so the "not logged in" case ends at the login screen rather than silently
  // doing nothing.
  NotificationService().onMessageTapped = (message) {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null) return;
    if (!AdminAuthService().isLoggedIn) return;
    final type = message.data['type'] ?? '';
    if (type == 'delivery_ready' || AdminAuthService().isDelivery) {
      nav.push(MaterialPageRoute(builder: (_) => const DeliveryDashboardScreen()));
    } else if (type == 'new_order') {
      nav.push(MaterialPageRoute(builder: (_) => const AdminOrdersScreen()));
    }
  };

  runApp(const DhanamStaffApp());
}

class DhanamStaffApp extends StatelessWidget {
  const DhanamStaffApp({super.key});

  /// Where a launch lands, given who is already signed in.
  ///
  /// The session is the admin one and it lasts 24 hours, so most mornings this
  /// is the login screen — which is the right default for a shared shop phone.
  static Widget home() {
    final auth = AdminAuthService();
    if (!auth.isLoggedIn) return const AdminLoginScreen();
    return auth.isDelivery
        ? const DeliveryDashboardScreen()
        : const SecureAdminDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanam Staff',
      theme: appTheme(),
      navigatorKey: NotificationService.navigatorKey,
      // Same clamp as the customer app: these screens have fixed-width rows and
      // pill badges that clip well before a phone's largest font setting.
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
