import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RazorpayCheckoutScreen extends StatefulWidget {
  final String keyId;
  final String orderId;
  final int amountInPaise;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String description;

  const RazorpayCheckoutScreen({
    super.key,
    required this.keyId,
    required this.orderId,
    required this.amountInPaise,
    required this.customerName,
    required this.customerPhone,
    this.customerEmail = '',
    this.description = 'Dhanam Store Order',
  });

  @override
  State<RazorpayCheckoutScreen> createState() => _RazorpayCheckoutScreenState();
}

class _RazorpayCheckoutScreenState extends State<RazorpayCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..addJavaScriptChannel(
        'RazorpayResult',
        onMessageReceived: (message) {
          if (_handled) return;
          _handled = true;
          final msg = message.message;
          if (msg.startsWith('success:')) {
            final paymentId = msg.substring(8);
            Navigator.pop(context, {'status': 'success', 'payment_id': paymentId});
          } else if (msg.startsWith('error:')) {
            final errorMsg = msg.substring(6);
            Navigator.pop(context, {'status': 'error', 'message': errorMsg});
          } else {
            Navigator.pop(context, {'status': 'dismissed'});
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.startsWith('upi://') || url.startsWith('tez://') || url.startsWith('phonepe://') || url.startsWith('paytmmp://') || url.startsWith('intent://')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_buildHtml());
  }

  String _escapeJs(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('"', '\\"')
      .replaceAll('\n', ' ')
      .replaceAll('\r', '');

  String _buildHtml() {
    final email = widget.customerEmail.isNotEmpty
        ? widget.customerEmail
        : 'customer@dhanamstore.com';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Payment</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #f0f0f0;
    display: flex; align-items: center; justify-content: center;
  }
  .container { text-align: center; padding: 20px; }
  .spinner {
    width: 44px; height: 44px; margin: 0 auto 20px;
    border: 4px solid #e0e0e0; border-top-color: #4CAF50;
    border-radius: 50%; animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .msg { color: #555; font-size: 15px; }
  .retry-btn {
    margin-top: 20px; padding: 12px 32px;
    background: #4CAF50; color: #fff; border: none;
    border-radius: 8px; font-size: 15px; cursor: pointer;
    display: none;
  }
</style>
</head>
<body>
<div class="container">
  <div class="spinner" id="spinner"></div>
  <p class="msg" id="msg">Preparing payment...</p>
  <button class="retry-btn" id="retryBtn" onclick="startPayment()">Retry Payment</button>
</div>

<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
<script>
  function startPayment() {
    document.getElementById('spinner').style.display = 'block';
    document.getElementById('msg').textContent = 'Opening Razorpay...';
    document.getElementById('retryBtn').style.display = 'none';

    try {
      var options = {
        key: '${_escapeJs(widget.keyId)}',
        amount: ${widget.amountInPaise},
        currency: 'INR',
        name: 'Dhanam Store',
        description: '${_escapeJs(widget.description)}',
        order_id: '${_escapeJs(widget.orderId)}',
        prefill: {
          name: '${_escapeJs(widget.customerName)}',
          contact: '${_escapeJs(widget.customerPhone)}',
          email: '${_escapeJs(email)}'
        },
        theme: { color: '#4CAF50' },
        handler: function(response) {
          document.getElementById('spinner').style.display = 'block';
          document.getElementById('msg').textContent = 'Payment successful! Redirecting...';
          RazorpayResult.postMessage('success:' + response.razorpay_payment_id);
        },
        modal: {
          ondismiss: function() {
            RazorpayResult.postMessage('dismiss');
          },
          confirm_close: true
        }
      };

      var rzp = new Razorpay(options);

      rzp.on('payment.failed', function(response) {
        RazorpayResult.postMessage('error:' + (response.error.description || 'Payment failed'));
      });

      rzp.open();
    } catch(e) {
      document.getElementById('spinner').style.display = 'none';
      document.getElementById('msg').textContent = 'Error: ' + e.message;
      document.getElementById('retryBtn').style.display = 'inline-block';
    }
  }

  if (typeof Razorpay !== 'undefined') {
    startPayment();
  } else {
    document.getElementById('msg').textContent = 'Loading payment SDK...';
    var checkReady = setInterval(function() {
      if (typeof Razorpay !== 'undefined') {
        clearInterval(checkReady);
        startPayment();
      }
    }, 500);
    setTimeout(function() {
      clearInterval(checkReady);
      if (typeof Razorpay === 'undefined') {
        document.getElementById('spinner').style.display = 'none';
        document.getElementById('msg').textContent = 'Could not load payment SDK. Check your internet connection.';
        document.getElementById('retryBtn').style.display = 'inline-block';
      }
    }, 15000);
  }
</script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (!_handled) {
              Navigator.pop(context, {'status': 'dismissed'});
            }
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.green)),
        ],
      ),
    );
  }
}
