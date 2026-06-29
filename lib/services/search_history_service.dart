import 'dart:convert';
import 'dart:io';
import '../config.dart';
import 'auth_service.dart';

/// Recent searches are stored per-user on the backend (in the user's record),
/// so each account sees only its own history — even on a shared device.
class SearchHistoryService {
  static final String _baseUrl = AppConfig.baseUrl;
  static const _maxItems = 10;
  static final SearchHistoryService _instance = SearchHistoryService._();
  factory SearchHistoryService() => _instance;
  SearchHistoryService._();

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  List<String> _history = [];

  List<String> get history => List.unmodifiable(_history);

  String? get _token => AuthService().token;

  Future<void> load() async {
    if (_token == null) {
      _history = [];
      return;
    }
    try {
      final req = await _client.getUrl(Uri.parse('$_baseUrl/auth/recent-searches'));
      req.headers.set('Authorization', 'Bearer $_token');
      final res = await req.close();
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      if (data is Map && data['searches'] != null) {
        _history = List<String>.from(data['searches']);
      }
    } catch (_) {}
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // Optimistic local update for instant UI feedback.
    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > _maxItems) {
      _history = _history.sublist(0, _maxItems);
    }
    if (_token == null) return;
    await _post('/auth/recent-searches', {'query': trimmed});
  }

  Future<void> remove(String query) async {
    _history.remove(query);
    if (_token == null) return;
    await _post('/auth/recent-searches/remove', {'query': query});
  }

  Future<void> clear() async {
    _history = [];
    if (_token == null) return;
    try {
      final req = await _client.deleteUrl(Uri.parse('$_baseUrl/auth/recent-searches'));
      req.headers.set('Authorization', 'Bearer $_token');
      await req.close();
    } catch (_) {}
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      final req = await _client.postUrl(Uri.parse('$_baseUrl$path'));
      req.headers.contentType = ContentType.json;
      req.headers.set('Authorization', 'Bearer $_token');
      req.write(jsonEncode(body));
      final res = await req.close();
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      // Server is the source of truth — sync to its authoritative list.
      if (data is Map && data['searches'] != null) {
        _history = List<String>.from(data['searches']);
      }
    } catch (_) {}
  }
}
