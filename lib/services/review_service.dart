import 'dart:convert';
import 'dart:io';
import '../config.dart';
import 'auth_service.dart';

class ReviewService {
  static final String _baseUrl = AppConfig.baseUrl;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<Map<String, dynamic>> getProductReviews(String productId) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl/reviews/product/$productId'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> submitReview({
    required String productId,
    required int rating,
    String title = '',
    required String comment,
  }) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/reviews/'));
    request.headers.contentType = ContentType.json;
    final token = AuthService().token;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode({
      'product_id': productId,
      'rating': rating,
      'title': title,
      'comment': comment,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      String detail = body;
      try {
        detail = (jsonDecode(body) as Map<String, dynamic>)['detail']?.toString() ?? body;
      } catch (_) {}
      throw Exception(detail);
    }
  }

  Future<void> markHelpful(String reviewId) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/reviews/$reviewId/helpful'));
    request.headers.contentType = ContentType.json;
    request.write('{}');
    await request.close();
  }
}
