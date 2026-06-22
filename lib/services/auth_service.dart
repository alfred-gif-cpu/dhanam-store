import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static final String _baseUrl = AppConfig.baseUrl;

  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final HttpClient _client = HttpClient();
  String? _token;
  Map<String, dynamic>? _user;
  bool _loaded = false;

  // Callback for when user changes — set by CartService
  static VoidCallback? onUserSwitch;

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String get userId => _user?['id'] ?? '';
  String get phone => _user?['phone'] ?? '';
  String get name => _user?['name'] ?? '';
  String get email => _user?['email'] ?? '';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userData = prefs.getString(_userKey);
    if (userData != null) {
      _user = jsonDecode(userData);
    }
    _loaded = true;
    if (_token != null) _fetchProfile();
    notifyListeners();
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    request.write(jsonEncode(body));
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    final result = jsonDecode(data) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(result['detail'] ?? 'Request failed');
    }
    return result;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    return jsonDecode(data) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    request.write(jsonEncode(body));
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    return jsonDecode(data) as Map<String, dynamic>;
  }

  Future<void> sendOtp(String phone) async {
    await _post('/auth/send-otp', {'phone': phone});
  }

  Future<bool> verifyOtp(String phone, String otp) async {
    final result = await _post('/auth/verify-otp', {'phone': phone, 'otp': otp});
    _token = result['token'];
    _user = {'id': result['user_id'], 'phone': phone, 'name': '', 'email': ''};

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_user));

    notifyListeners();
    onUserSwitch?.call();
    _fetchProfile();
    return result['is_new_user'] == true;
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await _get('/auth/me');
      _user = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(_user));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateProfile({String? name, String? email}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    await _put('/auth/profile', body);
    if (name != null) _user?['name'] = name;
    if (email != null) _user?['email'] = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
    onUserSwitch?.call();
  }
}
