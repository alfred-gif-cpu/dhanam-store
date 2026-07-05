import 'package:flutter/material.dart';
import '../models/address.dart';
import '../services/address_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import 'address/address_list_screen.dart';
import 'login_screen.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ApiService _api = ApiService();
  final AddressService _addrSvc = AddressService();
  final CartService _cart = CartService();
  int _step = 0;
  List<Address> _addresses = [];
  Address? _selectedAddress;
  String _deliverySlot = '';
  bool _loading = true;
  bool _placing = false;
  String? _addrError;

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
    setState(() { _loading = true; _addrError = null; });
    try {
      var addrs = await _addrSvc.getAddresses(AuthService().userId);
      if (addrs.isEmpty) {
        addrs = await _api.getAddresses(AuthService().userId);
      }
      setState(() {
        _addresses = addrs;
        final defaultAddr = addrs.where((a) => a.isDefault).toList();
        _selectedAddress = defaultAddr.isNotEmpty ? defaultAddr.first : (addrs.isNotEmpty ? addrs.first : null);
        _loading = false;
      });
    } catch (e) {
      setState(() { _addrError = e.toString(); _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Failed to load addresses'), behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'RETRY', onPressed: _loadAddresses)),
        );
      }
    }
  }

  bool get _canProceed {
    if (_step == 0) return _selectedAddress != null;
    if (_step == 1) return _deliverySlot.isNotEmpty;
    return true;
  }

  void _next() {
    if (_step < 2) {
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
    final grandTotal = _cart.grandTotal;
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
        'grand_total': grandTotal,
        'payment_method': 'cod',
        'delivery_slot': _deliverySlot,
        'address': _selectedAddress!.toJson(),
      });
      _cart.clear();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OrderSuccessScreen(
            orderNumber: result['order_number'] ?? '',
            grandTotal: grandTotal,
            deliverySlot: _deliverySlot,
            paymentMethod: 'cod',
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
          : _addrError != null && _addresses.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Could not load addresses', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: _loadAddresses, icon: const Icon(Icons.refresh, size: 18), label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                ]))
              : Column(
              children: [
                _buildStepper(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: [_buildAddressStep, _buildSlotStep, _buildReviewStep][_step](),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _loading ? null : _buildBottomBar(),
    );
  }

  Widget _buildStepper() {
    final steps = ['Address', 'Slot', 'Review'];
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
                    color: done ? Colors.blue : active ? Colors.blue : Colors.grey[300],
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text('${i + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.grey[600])),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(child: Text(steps[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.blue[800] : Colors.grey[500]))),
                if (i < steps.length - 1)
                  Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 4), color: done ? Colors.blue : Colors.grey[300])),
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
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressListScreen()));
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
                  border: Border.all(color: selected ? Colors.blue : Colors.grey[200]!, width: selected ? 2 : 1),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected ? Colors.blue[50] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        addr.label == 'Work' ? Icons.work_outline : Icons.home_outlined,
                        color: selected ? Colors.blue[700] : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(addr.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                            child: Text('Selected', style: TextStyle(fontSize: 10, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text(addr.fullName, style: const TextStyle(fontSize: 13)),
                      Text(addr.shortAddress, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text(addr.phone, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ])),
                    Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selected ? Colors.blue : Colors.grey[400]),
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
                color: selected ? Colors.blue[50] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? Colors.blue : Colors.grey[200]!, width: selected ? 2 : 1),
              ),
              child: Row(children: [
                Icon(Icons.schedule, size: 20, color: selected ? Colors.blue[700] : Colors.grey[400]),
                const SizedBox(width: 12),
                Text(timeOnly, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, color: selected ? Colors.blue[800] : null)),
                const Spacer(),
                if (selected) Icon(Icons.check_circle, size: 22, color: Colors.blue[700]),
              ]),
            ),
          );
        }),
      ],
    );
  }

  // ─── Step 3: Review ───
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(Icons.money, size: 22, color: Colors.orange[700]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Payment', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 4),
              const Text('Cash on Delivery', style: TextStyle(fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
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
            _billRow('Item total (incl. GST)', '₹${_cart.subtotal.toStringAsFixed(2)}'),
            _billRow('GST included', '₹${_cart.gstAmount.toStringAsFixed(2)}'),
            _billRow('Delivery', _cart.deliveryCharge == 0 ? 'FREE' : '₹${_cart.deliveryCharge.toStringAsFixed(0)}',
                valueColor: _cart.deliveryCharge == 0 ? Colors.blue : null),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Grand Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₹${_cart.grandTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
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
        Icon(icon, size: 22, color: Colors.blue[700]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 4),
          ...children,
        ])),
        GestureDetector(
          onTap: () => setState(() => _step = title == 'Delivery to' ? 0 : 1),
          child: Text('Change', style: TextStyle(fontSize: 13, color: Colors.blue[700], fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _billRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: Colors.grey[600]))),
        const SizedBox(width: 8),
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
    final labels = ['Continue', 'Continue', 'Place Order — ₹${_cart.grandTotal.toStringAsFixed(0)}'];
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
            backgroundColor: _step == 2 ? Colors.blue[700] : Colors.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _placing
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (_step == 2) const Icon(Icons.lock, size: 18),
                  if (_step == 2) const SizedBox(width: 8),
                  Text(labels[_step], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
        ),
      ),
    );
  }
}
