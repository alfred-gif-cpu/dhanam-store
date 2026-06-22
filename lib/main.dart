import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/delivery_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/admin_auth_service.dart';
import 'services/auth_service.dart';
import 'services/cart_service.dart';
import 'services/customer_service.dart';
import 'services/notification_service.dart';
import 'services/recently_viewed_service.dart';
import 'services/search_history_service.dart';
import 'services/wishlist_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AdminAuthService().load();
  await AuthService().load();
  await AuthService().logout();
  await CartService().load();
  WishlistService().load();
  SearchHistoryService().load();
  RecentlyViewedService().load();
  CustomerService().load();
  await NotificationService().init();

  // Tapping an order notification opens the right screen for the logged-in role
  NotificationService().onMessageTapped = (message) {
    final nav = NotificationService.navigatorKey.currentState;
    if (nav == null) return;
    final type = message.data['type'] ?? '';
    if (!AdminAuthService().isLoggedIn) return;
    if (type == 'delivery_ready' || AdminAuthService().isDelivery) {
      nav.push(MaterialPageRoute(builder: (_) => const DeliveryDashboardScreen()));
    } else if (type == 'new_order') {
      nav.push(MaterialPageRoute(builder: (_) => const AdminOrdersScreen()));
    }
  };

  runApp(const DhanamStoreApp());
}

class DhanamStoreApp extends StatelessWidget {
  const DhanamStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanam Store',
      theme: appTheme(),
      navigatorKey: NotificationService.navigatorKey,
      home: const LoginScreen(),
    );
  }
}
