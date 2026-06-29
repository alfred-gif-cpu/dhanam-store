import 'dart:convert';
import 'dart:io';
import '../config.dart';

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
    required String userId,
    required String userName,
    required int rating,
    String title = '',
    String comment = '',
  }) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/reviews/'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'product_id': productId,
      'user_id': userId,
      'user_name': userName,
      'rating': rating,
      'title': title,
      'comment': comment,
    }));
    final response = await request.close();
    if (response.statusCode != 200) {
      final body = await response.transform(utf8.decoder).join();
      throw Exception(body);
    }
  }

  Future<void> markHelpful(String reviewId) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/reviews/$reviewId/helpful'));
    request.headers.contentType = ContentType.json;
    request.write('{}');
    await request.close();
  }
}
