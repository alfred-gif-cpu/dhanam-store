import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentlyViewedService extends ChangeNotifier {
  static const _key = 'recently_viewed_ids';
  static const _maxItems = 20;
  static final RecentlyViewedService _instance = RecentlyViewedService._();
  factory RecentlyViewedService() => _instance;
  RecentlyViewedService._();

  final List<String> _ids = [];
  bool _loaded = false;

  List<String> get ids => List.unmodifiable(_ids);
  bool get hasItems => _ids.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) _ids.addAll(List<String>.from(jsonDecode(data)));
    _loaded = true;
  }

  Future<void> add(String productId) async {
    _ids.remove(productId);
    _ids.insert(0, productId);
    if (_ids.length > _maxItems) _ids.removeRange(_maxItems, _ids.length);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_ids));
  }
}
