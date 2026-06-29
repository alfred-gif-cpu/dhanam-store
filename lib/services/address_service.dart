import 'dart:convert';
import 'dart:io';
import '../config.dart';
import '../models/address.dart';

class AddressService {
  static final String _baseUrl = AppConfig.baseUrl;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<Map<String, dynamic>> _request(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$_baseUrl$path');
    late HttpClientRequest req;
    if (method == 'POST') {
      req = await _client.postUrl(uri);
    } else if (method == 'PUT') {
      req = await _client.putUrl(uri);
    } else if (method == 'DELETE') {
      req = await _client.deleteUrl(uri);
    } else {
      req = await _client.getUrl(uri);
    }

    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final data = jsonDecode(await res.transform(utf8.decoder).join());
    if (res.statusCode >= 400) throw Exception(data['detail'] ?? 'Request failed');
    return data;
  }

  Future<List<Address>> getAddresses(String customerId) async {
    final data = await _request('GET', '/addresses?customer_id=$customerId');
    return (data['addresses'] as List).map((a) => Address.fromJson(a)).toList();
  }

  Future<Address> getAddress(String addressId) async {
    final data = await _request('GET', '/addresses/$addressId');
    return Address.fromJson(data);
  }

  Future<String> addAddress(String customerId, Map<String, dynamic> address) async {
    address['customer_id'] = customerId;
    final data = await _request('POST', '/addresses', address);
    return data['id'];
  }

  Future<void> updateAddress(String addressId, Map<String, dynamic> address) async {
    await _request('PUT', '/addresses/$addressId', address);
  }

  Future<void> deleteAddress(String addressId) async {
    await _request('DELETE', '/addresses/$addressId');
  }

  Future<void> setDefault(String addressId) async {
    await _request('PUT', '/addresses/$addressId/default');
  }
}
