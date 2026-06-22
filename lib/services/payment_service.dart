import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../config.dart';
import '../screens/razorpay_checkout_screen.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._();
  factory PaymentService() => _instance;
  PaymentService._();

  static final String _baseUrl = AppConfig.baseUrl;

  Future<Map<String, dynamic>?> createRazorpayOrder({
    required double amount,
    required String receipt,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$_baseUrl/payments/create-order'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'amount': amount,
        'currency': 'INR',
        'receipt': receipt,
      }));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Create Razorpay order failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> openCheckout({
    required BuildContext context,
    required String keyId,
    required String orderId,
    required int amountInPaise,
    required String customerName,
    required String customerPhone,
    String customerEmail = '',
    String description = 'Dhanam Store Order',
  }) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RazorpayCheckoutScreen(
          keyId: keyId,
          orderId: orderId,
          amountInPaise: amountInPaise,
          customerName: customerName,
          customerPhone: customerPhone,
          customerEmail: customerEmail,
          description: description,
        ),
      ),
    );
    return result;
  }
}
