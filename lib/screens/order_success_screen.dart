import 'package:flutter/material.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String orderNumber;
  final double grandTotal;
  final String deliverySlot;
  final String paymentMethod;

  const OrderSuccessScreen({
    super.key,
    required this.orderNumber,
    required this.grandTotal,
    required this.deliverySlot,
    required this.paymentMethod,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _fadeController;
  late Animation<double> _checkScale;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _checkController.forward();
    Future.delayed(const Duration(milliseconds: 400), () => _fadeController.forward());
  }

  @override
  void dispose() {
    _checkController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String get _paymentLabel => switch (widget.paymentMethod) {
    'upi' => 'UPI Payment',
    'card' => 'Credit / Debit Card',
    _ => 'Cash on Delivery',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.popUntil(context, (route) => route.isFirst);
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),

                // Animated check
                ScaleTransition(
                  scale: _checkScale,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 48, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(children: [
                    const Text('Order Placed!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Your order has been confirmed', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  ]),
                ),
                const SizedBox(height: 32),

                // Order details card
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(children: [
                      _detailRow(Icons.receipt, 'Order Number', widget.orderNumber),
                      _divider(),
                      _detailRow(Icons.schedule, 'Delivery Slot', widget.deliverySlot),
                      _divider(),
                      _detailRow(Icons.payment, 'Payment', _paymentLabel),
                      _divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Row(children: [
                          Icon(Icons.currency_rupee, size: 20, color: Colors.green[700]),
                          const SizedBox(width: 10),
                          const Text('Total Paid', style: TextStyle(fontSize: 14)),
                        ]),
                        Text('₹${widget.grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                      ]),
                    ]),
                  ),
                ),

                const SizedBox(height: 20),

                // Tracking message
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      Icon(Icons.local_shipping_outlined, color: Colors.blue[700]),
                      const SizedBox(width: 10),
                      Expanded(child: Text('You can track your order from the Orders section in your profile',
                          style: TextStyle(fontSize: 13, color: Colors.blue[800]))),
                    ]),
                  ),
                ),

                const Spacer(),

                // Buttons
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text('Continue Shopping', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.grey[500]),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        const Spacer(),
        Flexible(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _divider() => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.grey[200]));
}
