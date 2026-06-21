import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../services/cart_service.dart';
import '../widgets/product_image.dart';
import 'checkout_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cart = CartService();

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_cart.isEmpty ? 'My Cart' : 'My Cart (${_cart.uniqueCount})'),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _showClearDialog,
            ),
        ],
      ),
      body: _cart.isEmpty ? _buildEmptyCart() : _buildCartContent(),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shopping_cart_outlined, size: 56, color: Colors.green[300]),
            ),
            const SizedBox(height: 24),
            const Text('Your cart is empty', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Looks like you haven\'t added\nanything to your cart yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[500], height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 50,
              width: 200,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Start Shopping', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartContent() {
    return Column(
      children: [
        // Free delivery progress
        if (_cart.amountForFreeDelivery > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 20, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add ₹${_cart.amountForFreeDelivery.toStringAsFixed(0)} more for FREE delivery',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange[800]),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _cart.subtotal / CartService.freeDeliveryThreshold,
                          backgroundColor: Colors.orange[100],
                          valueColor: AlwaysStoppedAnimation(Colors.orange[600]!),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text('Yay! You get FREE delivery on this order',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green[800])),
              ],
            ),
          ),

        // Savings banner
        if (_cart.totalSavings > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.savings_outlined, size: 20, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text('You\'re saving ₹${_cart.totalSavings.toStringAsFixed(0)} on this order!',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue[800])),
              ],
            ),
          ),

        // Cart items
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _cart.items.length,
            itemBuilder: (context, index) {
              final item = _cart.items[index];
              return Dismissible(
                key: ValueKey(item.productId),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red[400],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                ),
                onDismissed: (_) {
                  final removed = item;
                  _cart.remove(item.productId);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${removed.name} removed'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'UNDO',
                      textColor: Colors.yellow,
                      onPressed: () => _cart.updateQuantity(removed.productId, removed.quantity),
                    ),
                  ));
                },
                child: _CartItemCard(item: item, cart: _cart),
              );
            },
          ),
        ),

        // Bill summary
        _BillSummary(cart: _cart),
      ],
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Cart'),
        content: Text('Remove all ${_cart.uniqueCount} items from your cart?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { _cart.clear(); Navigator.pop(ctx); },
            child: const Text('Clear All', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final CartService cart;

  const _CartItemCard({required this.item, required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 76,
              height: 76,
              child: ProductImage(imageUrl: item.image, category: item.category),
            ),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('₹${item.price.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    if (item.originalPrice > item.price) ...[
                      const SizedBox(width: 4),
                      Text('₹${item.originalPrice.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[400], decoration: TextDecoration.lineThrough)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Quantity control
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _qtyBtn(Icons.remove, () => cart.decrement(item.productId)),
                          Container(
                            constraints: const BoxConstraints(minWidth: 32),
                            alignment: Alignment.center,
                            child: Text('${item.quantity}',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green[800])),
                          ),
                          _qtyBtn(Icons.add, () => cart.increment(item.productId)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Line total
                    Text('₹${item.total.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: Colors.green[700]),
      ),
    );
  }
}

class _BillSummary extends StatelessWidget {
  final CartService cart;

  const _BillSummary({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bill details header
          GestureDetector(
            onTap: () => _showBillDetails(context),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                const Text('Bill details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('₹${cart.grandTotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_up, size: 20, color: Colors.grey[600]),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Checkout button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Proceed to Checkout', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('₹${cart.grandTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBillDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Bill Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _row('Item total (${cart.itemCount} items)', cart.subtotal),
            const SizedBox(height: 8),
            _row('GST (18%)', cart.gstAmount),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Delivery fee', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    if (cart.deliveryCharge == 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(4)),
                        child: Text('FREE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green[700])),
                      ),
                    ],
                  ],
                ),
                Text(
                  cart.deliveryCharge == 0 ? '₹0' : '₹${cart.deliveryCharge.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: cart.deliveryCharge == 0 ? Colors.green : null,
                    decoration: cart.deliveryCharge == 0 ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            if (cart.totalSavings > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total savings', style: TextStyle(fontSize: 14, color: Colors.blue[700], fontWeight: FontWeight.w500)),
                  Text('-₹${cart.totalSavings.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 14, color: Colors.blue[700], fontWeight: FontWeight.w500)),
                ],
              ),
            ],
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('₹${cart.grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
