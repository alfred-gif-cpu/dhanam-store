import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'api_service.dart';
import 'auth_service.dart';

class WishlistService extends ChangeNotifier {
  static const _key = 'wishlist_v2';
  String get _userId => AuthService().isLoggedIn ? AuthService().userId : 'guest';
  static final WishlistService _instance = WishlistService._();
  factory WishlistService() => _instance;
  WishlistService._();

  final ApiService _api = ApiService();
  final List<Product> _items = [];
  final Set<String> _ids = {};
  bool _loaded = false;

  List<Product> get items => List.unmodifiable(_items);
  int get count => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool isWishlisted(String productId) => _ids.contains(productId);

  Future<void> load() async {
    if (_loaded) return;

    // Load local cache first for instant UI
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString(_key);
    if (local != null) {
      final list = jsonDecode(local) as List;
      for (final item in list) {
        final product = Product.fromJson(item);
        _items.add(product);
        _ids.add(product.id);
      }
    }
    _loaded = true;
    notifyListeners();

    // Sync from server in background
    try {
      final serverItems = await _api.getWishlist(_userId);
      _items.clear();
      _ids.clear();
      for (final p in serverItems) {
        _items.add(p);
        _ids.add(p.id);
      }
      notifyListeners();
      _saveLocal();
    } catch (_) {}
  }

  Future<void> toggle(Product product) async {
    if (_ids.contains(product.id)) {
      _ids.remove(product.id);
      _items.removeWhere((p) => p.id == product.id);
      notifyListeners();
      _saveLocal();
      try { await _api.removeFromWishlist(_userId, product.id); } catch (_) {}
    } else {
      _ids.add(product.id);
      _items.insert(0, product);
      notifyListeners();
      _saveLocal();
      try { await _api.addToWishlist(_userId, product.id); } catch (_) {}
    }
  }

  void _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _items.map((p) => {
      'id': p.id, 'name': p.name, 'category': p.category, 'brand': p.brand,
      'price': p.price, 'original_price': p.originalPrice,
      'image': p.image, 'stock': p.stock, 'description': p.description,
    }).toList();
    await prefs.setString(_key, jsonEncode(data));
  }
}
