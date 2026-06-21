import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/cart_service.dart';
import 'services/customer_service.dart';
import 'services/recently_viewed_service.dart';
import 'services/search_history_service.dart';
import 'services/wishlist_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService().load();
  await CartService().load();
  WishlistService().load();
  SearchHistoryService().load();
  RecentlyViewedService().load();
  CustomerService().load();
  runApp(const DhanamStoreApp());
}

class DhanamStoreApp extends StatelessWidget {
  const DhanamStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dhanam Store',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const HomeScreen(),
    );
  }
}
