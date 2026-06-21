import 'dart:convert';
import 'dart:io';

class OrderService {
  static const String _baseUrl = 'http://10.0.2.2:8000';
  final HttpClient _client = HttpClient();

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

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> order) => _post('/orders/create', order);
  Future<Map<String, dynamic>> getOrder(String orderId) => _get('/orders/by-id/$orderId');
  Future<Map<String, dynamic>> getCustomerOrders(String customerId, {int page = 1, String status = ''}) {
    var path = '/orders/customer/$customerId?page=$page';
    if (status.isNotEmpty) path += '&status=$status';
    return _get(path);
  }
  Future<Map<String, dynamic>> cancelOrder(String orderId, {String reason = 'Customer requested'}) =>
      _put('/orders/$orderId/cancel', {'reason': reason});
  Future<Map<String, dynamic>> trackOrder(String orderId) => _get('/orders/$orderId/track');
  Future<Map<String, dynamic>> reorder(String orderId) => _post('/orders/$orderId/reorder', {});
  Future<Map<String, dynamic>> getAnalytics() => _get('/admin/orders/analytics');
}
