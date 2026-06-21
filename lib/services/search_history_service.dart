import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryService {
  static const _key = 'recent_searches';
  static const _maxItems = 10;
  static final SearchHistoryService _instance = SearchHistoryService._();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._();

  List<String> _history = [];
  bool _loaded = false;

  List<String> get history => List.unmodifiable(_history);

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      _history = List<String>.from(jsonDecode(data));
    }
    _loaded = true;
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > _maxItems) {
      _history = _history.sublist(0, _maxItems);
    }
    await _save();
  }

  Future<void> remove(String query) async {
    _history.remove(query);
    await _save();
  }

  Future<void> clear() async {
    _history.clear();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_history));
  }
}
