import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import 'auth_service.dart';

class CartService extends ChangeNotifier {
  static final String _baseUrl = AppConfig.baseUrl;
  static final CartService _instance = CartService._();
  factory CartService() => _instance;
  CartService._();

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final List<CartItem> _items = [];
  bool _loaded = false;
  String _loadedForUser = '';

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int quantityOf(String productId) {
    final index = _items.indexWhere((e) => e.productId == productId);
    return index >= 0 ? _items[index].quantity : 0;
  }

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

  String get _userId => AuthService().isLoggedIn ? AuthService().userId : 'guest';
  String get _storageKey => 'cart_v4_$_userId';

  // ─── Load / Save ───────────────────────────────────────

  void _init() {
    AuthService.onUserSwitch = onUserChanged;
  }

  Future<void> load() async {
    _init();
    final currentUser = _userId;
    if (_loaded && _loadedForUser == currentUser) return;

    _items.clear();
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('cart_v4_$currentUser');
    if (data != null) {
      final list = jsonDecode(data) as List;
      _items.addAll(list.map((e) => CartItem.fromJson(e)));
    }
    _loaded = true;
    _loadedForUser = currentUser;
    notifyListeners();
    _syncFromServer();
  }

  Future<void> reloadForCurrentUser() async {
    _loaded = false;
    _loadedForUser = '';
    await load();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  // ─── Server sync ───────────────────────────────────────

  Future<void> _syncToServer() async {
    if (_userId == 'guest') return;
    try {
      final req = await _client.postUrl(Uri.parse('$_baseUrl/cart/sync'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'customer_id': _userId,
        'items': _items.map((e) => {
          'product_id': e.productId,
          'product_name': e.name,
          'price': e.price,
          'original_price': e.originalPrice,
          'quantity': e.quantity,
          'image': e.image,
          'category': e.category,
          'subtotal': e.total,
        }).toList(),
      }));
      await (await req.close()).drain();
    } catch (_) {}
  }

  Future<void> _syncFromServer() async {
    if (_userId == 'guest') return;
    try {
      final req = await _client.getUrl(Uri.parse('$_baseUrl/cart?customer_id=$_userId'));
      final res = await req.close();
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      final serverItems = (data['items'] as List?) ?? [];
      if (serverItems.isNotEmpty && _items.isEmpty) {
        _items.clear();
        for (final item in serverItems) {
          _items.add(CartItem(
            productId: item['product_id'] ?? '',
            name: item['product_name'] ?? '',
            price: (item['price'] ?? 0).toDouble(),
            originalPrice: (item['original_price'] ?? 0).toDouble(),
            quantity: item['quantity'] ?? 1,
            image: item['image'] ?? '',
            category: item['category'] ?? '',
          ));
        }
        _saveLocal();
        notifyListeners();
      } else if (_items.isNotEmpty) {
        _syncToServer();
      }
    } catch (_) {}
  }

  Future<void> refresh() async => _syncFromServer();

  // ─── Cart operations ───────────────────────────────────

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
    _saveLocal();
    _syncToServer();
  }

  void increment(String productId) {
    final index = _items.indexWhere((e) => e.productId == productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
      _saveLocal();
      _syncToServer();
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
    _saveLocal();
    _syncToServer();
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
    _saveLocal();
    _syncToServer();
  }

  void remove(String productId) {
    _items.removeWhere((e) => e.productId == productId);
    notifyListeners();
    _saveLocal();
    _syncToServer();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _saveLocal();
    if (_userId != 'guest') {
      _client.deleteUrl(Uri.parse('$_baseUrl/cart/clear?customer_id=$_userId'))
          .then((req) => req.close()).then((res) => res.drain()).catchError((_) {});
    }
  }

  void onUserChanged() {
    _loaded = false;
    _loadedForUser = '';
    _items.clear();
    notifyListeners();
    load();
  }
}
