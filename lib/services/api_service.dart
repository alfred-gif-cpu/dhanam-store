import 'dart:convert';
import 'dart:io';
import '../config.dart';
import '../models/product.dart';
import '../models/banner.dart';
import '../models/address.dart';
import '../models/category.dart';
import '../models/order.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  NetworkException([this.message = 'No internet connection. Please check your network.']);
  @override
  String toString() => message;
}

class ApiService {
  static final String _baseUrl = AppConfig.baseUrl;

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      late HttpClientRequest request;
      switch (method) {
        case 'GET':
          request = await _client.getUrl(uri);
        case 'POST':
          request = await _client.postUrl(uri);
        case 'PUT':
          request = await _client.putUrl(uri);
        case 'DELETE':
          request = await _client.deleteUrl(uri);
        default:
          request = await _client.getUrl(uri);
      }

      final token = AuthService().token;
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(data));
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 401) {
        await AuthService().logout();
        throw ApiException(401, 'Session expired. Please log in again.');
      }

      if (response.statusCode >= 400) {
        String message = 'Request failed';
        try {
          final errorBody = jsonDecode(body) as Map<String, dynamic>;
          message = errorBody['detail']?.toString() ?? message;
        } catch (_) {}
        throw ApiException(response.statusCode, message);
      }

      if (method == 'DELETE' && body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException {
      throw NetworkException();
    } on HttpException {
      throw NetworkException('Server unreachable. Please try again later.');
    } on HandshakeException {
      throw NetworkException('Secure connection failed. Please try again.');
    }
  }

  Future<Map<String, dynamic>> _get(String path) => _request('GET', path);
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) => _request('POST', path, data: data);
  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> data) => _request('PUT', path, data: data);
  Future<void> _delete(String path) async => await _request('DELETE', path);

  // Products
  Future<ProductResponse> getProducts({int page = 1, int limit = 20, String? category}) async {
    var path = '/products?page=$page&limit=$limit';
    if (category != null) path += '&category=${Uri.encodeComponent(category)}';
    return ProductResponse.fromJson(await _get(path));
  }

  Future<Product> getProduct(String id) async => Product.fromJson(await _get('/products/$id'));

  Future<List<Category>> getCategories() async {
    final data = await _get('/categories');
    return (data['categories'] as List).map((c) => Category.fromJson(c)).toList();
  }

  Future<ProductResponse> searchProducts(String query, {int page = 1, int limit = 20}) async {
    return ProductResponse.fromJson(
        await _get('/search?q=${Uri.encodeComponent(query)}&page=$page&limit=$limit'));
  }

  Future<SearchSuggestions> getSearchSuggestions(String query) async {
    final data = await _get('/search/suggestions?q=${Uri.encodeComponent(query)}');
    return SearchSuggestions.fromJson(data);
  }

  Future<List<Product>> getFeaturedProducts({int limit = 10}) async {
    final data = await _get('/products/featured?limit=$limit');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  Future<List<Product>> getFlashDeals({int limit = 10}) async {
    final data = await _get('/products/flash-deals?limit=$limit');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  Future<List<Product>> getTrending({int limit = 10}) async {
    final data = await _get('/products/trending?limit=$limit');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  Future<List<Product>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final data = await _get('/products/by-ids?ids=${ids.join(",")}');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  Future<List<Product>> getBestsellers({int limit = 10}) async {
    final data = await _get('/products/bestsellers?limit=$limit');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  // Banners
  Future<List<HomeBanner>> getBanners() async {
    final data = await _get('/banners');
    return (data['banners'] as List).map((b) => HomeBanner.fromJson(b)).toList();
  }

  // Wishlist
  Future<List<Product>> getWishlist(String userId) async {
    final data = await _get('/wishlist/$userId');
    return (data['products'] as List).map((p) => Product.fromJson(p)).toList();
  }

  Future<void> addToWishlist(String userId, String productId) async {
    await _post('/wishlist/$userId/add', {'product_id': productId});
  }

  Future<void> removeFromWishlist(String userId, String productId) async {
    await _post('/wishlist/$userId/remove', {'product_id': productId});
  }

  // Addresses
  Future<List<Address>> getAddresses(String userId) async {
    try {
      final data = await _get('/addresses?customer_id=$userId');
      return (data['addresses'] as List).map((a) => Address.fromJson(a)).toList();
    } catch (_) {
      try {
        final data = await _get('/addresses/$userId');
        return (data['addresses'] as List).map((a) => Address.fromJson(a)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<String> addAddress(String userId, Map<String, dynamic> address) async {
    address['customer_id'] = userId;
    address['name'] = address['name'] ?? address['full_name'] ?? '';
    address['house_no'] = address['house_no'] ?? address['line1'] ?? '';
    address['street'] = address['street'] ?? '';
    final data = await _post('/addresses', address);
    return data['id'];
  }

  Future<void> updateAddress(String addressId, Map<String, dynamic> address) async {
    await _put('/addresses/$addressId', address);
  }

  Future<void> deleteAddress(String addressId) async {
    await _delete('/addresses/$addressId');
  }

  // Orders
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> order) async {
    return await _post('/orders/create', order);
  }

  Future<List<Order>> getOrders(String userId) async {
    final data = await _get('/orders/$userId');
    return (data['orders'] as List).map((o) => Order.fromJson(o)).toList();
  }
}

class SearchSuggestions {
  final List<String> names;
  final List<String> brands;
  final List<String> categories;

  SearchSuggestions({required this.names, required this.brands, required this.categories});

  bool get isEmpty => names.isEmpty && brands.isEmpty && categories.isEmpty;

  factory SearchSuggestions.fromJson(Map<String, dynamic> json) {
    return SearchSuggestions(
      names: List<String>.from(json['names'] ?? []),
      brands: List<String>.from(json['brands'] ?? []),
      categories: List<String>.from(json['categories'] ?? []),
    );
  }
}

class ProductResponse {
  final List<Product> products;
  final int total;
  final int page;
  final int pages;

  ProductResponse({required this.products, required this.total, required this.page, required this.pages});

  factory ProductResponse.fromJson(Map<String, dynamic> json) {
    return ProductResponse(
      products: (json['products'] as List).map((p) => Product.fromJson(p)).toList(),
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pages: json['pages'] ?? 1,
    );
  }
}
