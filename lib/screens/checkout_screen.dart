import 'package:flutter/material.dart';
import '../models/address.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import 'addresses_screen.dart';
import 'login_screen.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ApiService _api = ApiService();
  final CartService _cart = CartService();

  int _step = 0;
  List<Address> _addresses = [];
  Address? _selectedAddress;
  String _deliverySlot = '';
  String _paymentMethod = 'cod';
  bool _loading = true;
  bool _placing = false;

  final _slots = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    if (!AuthService().isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      });
      return;
    }
    _generateSlots();
    _loadAddresses();
  }

  void _generateSlots() {
    final now = DateTime.now();
    final labels = ['Today', 'Tomorrow'];
    for (int d = 0; d < 2; d++) {
      final day = now.add(Duration(days: d));
      final label = d < 2 ? labels[d] : '${day.day}/${day.month}';
      for (final window in ['9 AM – 12 PM', '12 PM – 3 PM', '3 PM – 6 PM', '6 PM – 9 PM']) {
        _slots.add({'label': '$label, $window', 'value': '${day.toIso8601String().split("T").first} $window'});
      }
    }
    _deliverySlot = _slots.first['value']!;
  }

  Future<void> _loadAddresses() async {
    try {
      final addrs = await _api.getAddresses(AuthService().userId);
      setState(() {
        _addresses = addrs;
        if (addrs.isNotEmpty) _selectedAddress = addrs.first;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  bool get _canProceed {
    if (_step == 0) return _selectedAddress != null;
    if (_step == 1) return _deliverySlot.isNotEmpty;
    if (_step == 2) return _paymentMethod.isNotEmpty;
    return true;
  }

  void _next() {
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _placeOrder();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _placeOrder() async {
    setState(() => _placing = true);
    try {
      final result = await _api.createOrder({
        'user_id': AuthService().userId,
        'items': _cart.items.map((e) => {
          'product_id': e.productId,
          'name': e.name,
          'price': e.price,
          'quantity': e.quantity,
          'image': e.image,
        }).toList(),
        'subtotal': _cart.subtotal,
        'gst': _cart.gstAmount,
        'delivery_fee': _cart.deliveryCharge,
        'grand_total': _cart.grandTotal,
        'payment_method': _paymentMethod,
        'delivery_slot': _deliverySlot,
        'address': _selectedAddress!.toJson(),
      });
      _cart.clear();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OrderSuccessScreen(
            orderNumber: result['order_number'] ?? '',
            grandTotal: _cart.grandTotal,
            deliverySlot: _deliverySlot,
            paymentMethod: _paymentMethod,
          )),
        );
      }
    } catch (e) {
      setState(() => _placing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Checkout'),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _step > 0 ? _back : () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildStepper(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: [_buildAddressStep, _buildSlotStep, _buildPaymentStep, _buildReviewStep][_step](),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _loading ? null : _buildBottomBar(),
    );
  }

  Widget _buildStepper() {
    final steps = ['Address', 'Slot', 'Payment', 'Review'];
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      color: Colors.white,
      child: Row(
        children: List.generate(steps.length, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? Colors.green : active ? Colors.green : Colors.grey[300],
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text('${i + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.grey[600])),
                  ),
                ),
                const SizedBox(width: 4),
                Text(steps[i], style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.green[800] : Colors.grey[500])),
                if (i < steps.length - 1)
                  Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 4), color: done ? Colors.green : Colors.grey[300])),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── Step 1: Address ───
  Widget _buildAddressStep() {
    return ListView(
      key: const ValueKey('step-address'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Deliver to', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressesScreen()));
                _loadAddresses();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add New'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_addresses.isEmpty)
          _emptyCard(Icons.location_off, 'No addresses saved', 'Add a delivery address to continue')
        else
          ..._addresses.map((addr) {
            final selected = _selectedAddress?.id == addr.id;
            return GestureDetector(
              onTap: () => setState(() => _selectedAddress = addr),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: selected ? Colors.green : Colors.grey[200]!, width: selected ? 2 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected ? Colors.green[50] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        addr.label == 'Work' ? Icons.work_outline : Icons.home_outlined,
                        color: selected ? Colors.green[700] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(addr.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(6)),
                            child: Text('Selected', style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text(addr.fullName, style: const TextStyle(fontSize: 13)),
                      Text(addr.shortAddress, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text(addr.phone, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ])),
                    Radio<String>(value: addr.id, groupValue: _selectedAddress?.id,
                        onChanged: (_) => setState(() => _selectedAddress = addr), activeColor: Colors.green),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ─── Step 2: Delivery Slot ───
  Widget _buildSlotStep() {
    return ListView(
      key: const ValueKey('step-slot'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Choose delivery slot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Select a convenient time for delivery', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 16),

        // Today
        _slotSection('Today', _slots.sublist(0, 4)),
        const SizedBox(height: 16),
        _slotSection('Tomorrow', _slots.sublist(4, 8)),
      ],
    );
  }

  Widget _slotSection(String title, List<Map<String, String>> slots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
        const SizedBox(height: 8),
        ...slots.map((slot) {
          final selected = _deliverySlot == slot['value'];
          final timeOnly = slot['label']!.split(', ').last;
          return GestureDetector(
            onTap: () => setState(() => _deliverySlot = slot['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected ? Colors.green[50] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? Colors.green : Colors.grey[200]!, width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(Icons.schedule, size: 20, color: selected ? Colors.green[700] : Colors.grey[400]),
                const SizedBox(width: 12),
                Text(timeOnly, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, color: selected ? Colors.green[800] : null)),
                const Spacer(),
                if (selected) Icon(Icons.check_circle, size: 22, color: Colors.green[700]),
              ]),
            ),
          );
        }),
      ],
    );
  }

  // ─── Step 3: Payment ───
  Widget _buildPaymentStep() {
    return ListView(
      key: const ValueKey('step-payment'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Payment method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Choose how you\'d like to pay', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 16),
        _paymentOption('upi', 'UPI Payment', 'Google Pay, PhonePe, Paytm', Icons.qr_code_2, Colors.purple),
        _paymentOption('card', 'Credit / Debit Card', 'Visa, Mastercard, RuPay', Icons.credit_card, Colors.blue),
        _paymentOption('cod', 'Cash on Delivery', 'Pay when your order arrives', Icons.money, Colors.orange),
      ],
    );
  }

  Widget _paymentOption(String value, String title, String subtitle, IconData icon, Color color) {
    final selected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : Colors.grey[200]!, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: selected ? color : null)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ])),
          Radio<String>(value: value, groupValue: _paymentMethod,
              onChanged: (v) => setState(() => _paymentMethod = v!), activeColor: color),
        ]),
      ),
    );
  }

  // ─── Step 4: Review ───
  Widget _buildReviewStep() {
    return ListView(
      key: const ValueKey('step-review'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Order review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // Address summary
        _reviewCard(Icons.location_on, 'Delivery to', [
          Text('${_selectedAddress?.label} — ${_selectedAddress?.fullName}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(_selectedAddress?.shortAddress ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ]),
        const SizedBox(height: 10),

        // Slot summary
        _reviewCard(Icons.schedule, 'Delivery slot', [
          Text(_deliverySlot, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),

        // Payment summary
        _reviewCard(Icons.payment, 'Payment', [
          Text(
            _paymentMethod == 'upi' ? 'UPI Payment' : _paymentMethod == 'card' ? 'Credit / Debit Card' : 'Cash on Delivery',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ]),
        const SizedBox(height: 16),

        // Items
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_cart.itemCount} items', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._cart.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.shopping_bag_outlined, size: 20, color: Colors.grey),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${item.quantity} × ₹${item.price.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ])),
                Text('₹${item.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            )),
            const Divider(height: 20),
            _billRow('Subtotal', '₹${_cart.subtotal.toStringAsFixed(2)}'),
            _billRow('GST (18%)', '₹${_cart.gstAmount.toStringAsFixed(2)}'),
            _billRow('Delivery', _cart.deliveryCharge == 0 ? 'FREE' : '₹${_cart.deliveryCharge.toStringAsFixed(0)}',
                valueColor: _cart.deliveryCharge == 0 ? Colors.green : null),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Grand Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₹${_cart.grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
            ]),
          ]),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _reviewCard(IconData icon, String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: Colors.green[700]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          ...children,
        ])),
        GestureDetector(
          onTap: () => setState(() => _step = title == 'Delivery to' ? 0 : title == 'Delivery slot' ? 1 : 2),
          child: Text('Change', style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _billRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: 14, color: valueColor)),
      ]),
    );
  }

  Widget _emptyCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(icon, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700])),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final labels = ['Continue', 'Continue', 'Continue', 'Place Order — ₹${_cart.grandTotal.toStringAsFixed(0)}'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: _canProceed && !_placing ? _next : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _step == 3 ? Colors.green[700] : Colors.green,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _placing
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_step == 3) const Icon(Icons.lock, size: 18),
                  if (_step == 3) const SizedBox(width: 8),
                  Text(labels[_step], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
        ),
      ),
    );
  }
}
