import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerService extends ChangeNotifier {
  static const _key = 'customer_data';
  static const String _baseUrl = 'http://10.0.2.2:8000';
  static final CustomerService _instance = CustomerService._();
  factory CustomerService() => _instance;
  CustomerService._();

  final HttpClient _client = HttpClient();
  Map<String, dynamic>? _customer;
  bool _loaded = false;

  Map<String, dynamic>? get customer => _customer;
  bool get isRegistered => _customer != null;
  String get customerId => _customer?['customer_id'] ?? '';
  String get name => _customer?['name'] ?? '';
  String get email => _customer?['email'] ?? '';
  String get phone => _customer?['phone'] ?? '';
  String get profileImage => _customer?['profile_image'] ?? '';
  String get gender => _customer?['gender'] ?? '';
  String get dateOfBirth => _customer?['date_of_birth'] ?? '';
  double get walletBalance => (_customer?['wallet_balance'] ?? 0).toDouble();
  int get loyaltyPoints => (_customer?['loyalty_points'] ?? 0).toInt();
  List<dynamic> get addresses => _customer?['addresses'] ?? [];

  Future<Map<String, dynamic>> _get(String path) async {
    final req = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join());
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final req = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
    return data;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final req = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Failed');
    return data;
  }

  Future<void> _delete(String path) async {
    final req = await _client.deleteUrl(Uri.parse('$_baseUrl$path'));
    await (await req.close()).drain();
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) _customer = jsonDecode(data);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_customer != null) {
      await prefs.setString(_key, jsonEncode(_customer));
    } else {
      await prefs.remove(_key);
    }
  }

  Future<void> register(String phone, String name, {String email = ''}) async {
    final result = await _post('/customers/register', {'phone': phone, 'name': name, 'email': email});
    await fetchProfile(result['customer_id']);
  }

  Future<void> fetchProfile(String custId) async {
    _customer = await _get('/customers/$custId');
    await _save();
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? email, String? gender, String? dob}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (gender != null) body['gender'] = gender;
    if (dob != null) body['date_of_birth'] = dob;
    await _put('/customers/$customerId', body);
    body.forEach((k, v) => _customer?[k] = v);
    await _save();
    notifyListeners();
  }

  Future<void> addAddress(Map<String, dynamic> address) async {
    await _post('/customers/$customerId/addresses', address);
    await fetchProfile(customerId);
  }

  Future<void> editAddress(String addressId, Map<String, dynamic> data) async {
    await _put('/customers/$customerId/addresses/$addressId', data);
    await fetchProfile(customerId);
  }

  Future<void> deleteAddress(String addressId) async {
    await _delete('/customers/$customerId/addresses/$addressId');
    await fetchProfile(customerId);
  }

  Future<void> setDefaultAddress(String addressId) async {
    await _put('/customers/$customerId/addresses/$addressId/default', {});
    await fetchProfile(customerId);
  }

  Future<void> addLoyaltyPoints(int points) async {
    await _post('/customers/$customerId/loyalty/add', {'points': points});
    _customer?['loyalty_points'] = loyaltyPoints + points;
    await _save();
    notifyListeners();
  }

  Future<void> redeemLoyaltyPoints(int points) async {
    await _post('/customers/$customerId/loyalty/redeem', {'points': points});
    _customer?['loyalty_points'] = loyaltyPoints - points;
    await _save();
    notifyListeners();
  }

  Future<void> walletCredit(double amount, {String reason = 'top_up'}) async {
    await _post('/customers/$customerId/wallet/credit', {'amount': amount, 'reason': reason});
    _customer?['wallet_balance'] = walletBalance + amount;
    await _save();
    notifyListeners();
  }

  Future<void> walletDebit(double amount, {String reason = 'purchase'}) async {
    await _post('/customers/$customerId/wallet/debit', {'amount': amount, 'reason': reason});
    _customer?['wallet_balance'] = walletBalance - amount;
    await _save();
    notifyListeners();
  }

  Future<Map<String, dynamic>> getWalletTransactions({int page = 1}) async {
    return _get('/customers/$customerId/wallet/transactions?page=$page');
  }

  Future<Map<String, dynamic>> getOrderHistory({int page = 1}) async {
    return _get('/customers/$customerId/orders?page=$page');
  }

  void logout() {
    _customer = null;
    _save();
    notifyListeners();
  }
}
