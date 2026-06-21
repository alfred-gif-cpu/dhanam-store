import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

class CartService extends ChangeNotifier {
  static const _key = 'cart_items_v2';
  static final CartService _instance = CartService._();
  factory CartService() => _instance;
  CartService._();

  final List<CartItem> _items = [];
  bool _loaded = false;

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);
  int get uniqueCount => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  static const double gstRate = 0.18;
  static const double freeDeliveryThreshold = 499;
  static const double deliveryFee = 30;

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.total);
  double get totalSavings => _items.fold(0.0, (sum, item) => sum + item.savings);
  double get gstAmount => subtotal * gstRate;
  double get deliveryCharge => subtotal >= freeDeliveryThreshold ? 0 : deliveryFee;
  double get grandTotal => subtotal + gstAmount + deliveryCharge;
  double get amountForFreeDelivery => subtotal >= freeDeliveryThreshold ? 0 : freeDeliveryThreshold - subtotal;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      final list = jsonDecode(data) as List;
      _items.addAll(list.map((e) => CartItem.fromJson(e)));
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  void addProduct(Product product, int quantity) {
    final index = _items.indexWhere((e) => e.productId == product.id);
    if (index >= 0) {
      _items[index].quantity += quantity;
    } else {
      _items.add(CartItem(
        productId: product.id,
        name: product.name,
        image: product.image,
        category: product.category,
        price: product.price,
        originalPrice: product.originalPrice,
        quantity: quantity,
      ));
    }
    notifyListeners();
    _save();
  }

  void increment(String productId) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
      _save();
    }
  }

  void decrement(String productId) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index < 0) return;
    if (_items[index].quantity <= 1) {
      _items.removeAt(index);
    } else {
      _items[index].quantity--;
    }
    notifyListeners();
    _save();
  }

  void updateQuantity(String productId, int quantity) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index < 0) return;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      _items[index].quantity = quantity;
    }
    notifyListeners();
    _save();
  }

  void remove(String productId) {
    _items.removeWhere((e) => e.productId == productId);
    notifyListeners();
    _save();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _save();
  }
}
