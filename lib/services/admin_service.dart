import 'dart:convert';
import 'dart:io';
import '../config.dart';

class AdminService {
  static final String _baseUrl = AppConfig.baseUrl;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<Map<String, dynamic>> _get(String path) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join());
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join());
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> data) async {
    final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(data));
    final response = await request.close();
    return jsonDecode(await response.transform(utf8.decoder).join());
  }

  Future<void> _delete(String path) async {
    final request = await _client.deleteUrl(Uri.parse('$_baseUrl$path'));
    await (await request.close()).drain();
  }

  Future<Map<String, dynamic>> getStats() => _get('/admin/stats');

  Future<Map<String, dynamic>> getOrders({int page = 1, String? status}) async {
    var path = '/admin/orders?page=$page';
    if (status != null) path += '&status=$status';
    return _get(path);
  }

  Future<void> updateOrderStatus(String orderId, String status) =>
      _put('/admin/orders/$orderId/status', {'status': status});

  Future<Map<String, dynamic>> getUsers({int page = 1}) => _get('/admin/users?page=$page');

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> product) => _post('/admin/products', product);
  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> product) => _put('/admin/products/$id', product);
  Future<void> deleteProduct(String id) => _delete('/admin/products/$id');
  Future<void> toggleFeatured(String id, bool featured) =>
      _put('/admin/products/$id/featured', {'featured': featured});
}
