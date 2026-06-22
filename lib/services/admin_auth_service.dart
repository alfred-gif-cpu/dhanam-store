import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AdminAuthService extends ChangeNotifier {
  static const _tokenKey = 'admin_token';
  static const _dataKey = 'admin_data';
  static final String _baseUrl = AppConfig.baseUrl;

  static final AdminAuthService _instance = AdminAuthService._();
  factory AdminAuthService() => _instance;
  AdminAuthService._();

  final HttpClient _client = HttpClient();
  String? _token;
  Map<String, dynamic>? _admin;
  bool _loaded = false;

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String get email => _admin?['email'] ?? '';
  String get name => _admin?['name'] ?? 'Admin';
  String get role => _admin?['role'] ?? 'owner';
  bool get isOwner => role == 'owner';
  bool get isDelivery => role == 'delivery';
  bool get mustChangePassword => _admin?['must_change_password'] == true;

  Future<void> load() async {
    if (_loaded) return;
    // Admin must always log in — never restore session
    _token = null;
    _admin = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_dataKey);
    _loaded = true;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final req = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    req.headers.contentType = ContentType.json;
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.write(jsonEncode(body));
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
    return data;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final req = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
    return data;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final req = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    req.headers.contentType = ContentType.json;
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.write(jsonEncode(body));
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
    return data;
  }

  Future<bool> login(String email, String password) async {
    final result = await _post('/admin/login', {'email': email, 'password': password});
    _token = result['token'];
    _admin = {
      'email': result['email'],
      'name': result['name'],
      'role': result['role'] ?? 'owner',
      'must_change_password': result['must_change_password'],
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_dataKey, jsonEncode(_admin));
    notifyListeners();
    return result['must_change_password'] == true;
  }

  // ─── Staff management (owner) ───
  Future<Map<String, dynamic>> getStaff() => _get('/admin/staff');
  Future<void> createStaff({required String name, required String email, String phone = '', required String password}) =>
      _post('/admin/staff', {'name': name, 'email': email, 'phone': phone, 'password': password});
  Future<void> deleteStaff(String id) => deleteAdmin('/admin/staff/$id');

  // ─── Delivery (staff) ───
  Future<Map<String, dynamic>> getDeliveryOrders() => _get('/admin/delivery/orders');
  Future<void> pickupOrder(String orderId) => _put('/admin/delivery/orders/$orderId/pickup', {});
  Future<void> markDelivered(String orderId) => _put('/admin/delivery/orders/$orderId/delivered', {});

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _put('/admin/change-password', {'current_password': currentPassword, 'new_password': newPassword});
    _admin?['must_change_password'] = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey, jsonEncode(_admin));
    notifyListeners();
  }

  Future<Map<String, dynamic>> getDashboard() => _get('/admin/dashboard');
  Future<Map<String, dynamic>> getProducts({int page = 1, String q = ''}) =>
      _get('/admin/products?page=$page${q.isNotEmpty ? '&q=${Uri.encodeComponent(q)}' : ''}');
  Future<Map<String, dynamic>> getCustomers({int page = 1, String q = '', String status = ''}) =>
      _get('/admin/customers?page=$page${q.isNotEmpty ? '&q=${Uri.encodeComponent(q)}' : ''}${status.isNotEmpty ? '&status=$status' : ''}');
  Future<Map<String, dynamic>> getOrders({int page = 1, String status = '', String q = ''}) =>
      _get('/admin/orders?page=$page${status.isNotEmpty ? '&status=$status' : ''}${q.isNotEmpty ? '&q=${Uri.encodeComponent(q)}' : ''}');
  Future<Map<String, dynamic>> getInventory({int page = 1, String filter = ''}) =>
      _get('/admin/inventory?page=$page${filter.isNotEmpty ? '&filter=$filter' : ''}');
  Future<Map<String, dynamic>> getLogs({int page = 1}) => _get('/admin/logs?page=$page');

  Future<void> updateOrderStatus(String orderId, String status) =>
      _put('/admin/orders/$orderId/status', {'status': status});
  Future<void> updateStock(String productId, int stock) =>
      _put('/admin/inventory/$productId', {'stock': stock});
  Future<void> receiveStock(String productId, int quantity) =>
      _put('/admin/inventory/$productId/receive', {'quantity': quantity});
  Future<void> blockCustomer(String customerId) => _put('/admin/customers/$customerId/block', {});
  Future<void> unblockCustomer(String customerId) => _put('/admin/customers/$customerId/unblock', {});

  Future<Map<String, dynamic>> postAdmin(String path, Map<String, dynamic> body) => _post(path, body);
  Future<Map<String, dynamic>> putAdmin(String path, Map<String, dynamic> body) => _put(path, body);
  Future<void> deleteAdmin(String path) async {
    final req = await _client.deleteUrl(Uri.parse('$_baseUrl$path'));
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
  }

  Future<void> logout() async {
    _token = null;
    _admin = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_dataKey);
    notifyListeners();
  }
}
