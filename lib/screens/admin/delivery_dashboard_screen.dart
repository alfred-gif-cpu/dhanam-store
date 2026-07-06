import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/admin_auth_service.dart';
import '../../theme.dart';
import 'admin_login_screen.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  final _auth = AdminAuthService();
  List<dynamic> _orders = [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _auth.getDeliveryOrders();
      if (mounted) {
        setState(() {
          _orders = data['orders'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickup(String orderId) async {
    setState(() => _busyId = orderId);
    try {
      await _auth.pickupOrder(orderId);
      await _load();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delivered(String orderId) async {
    setState(() => _busyId = orderId);
    try {
      await _auth.markDelivered(orderId);
      await _load();
      _toast('Marked delivered');
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _navigate(Map<String, dynamic> addr) async {
    final lat = (addr['latitude'] ?? 0).toDouble();
    final lng = (addr['longitude'] ?? 0).toDouble();
    Uri uri;
    if (lat != 0 && lng != 0) {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      );
    } else {
      final q = [
        addr['house_no'],
        addr['street'],
        addr['city'],
        addr['pincode'],
      ].where((s) => s != null && s.toString().isNotEmpty).join(', ');
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
      );
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _auth.logout();
              Navigator.pop(ctx);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                (r) => false,
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // This is the top of the delivery section's navigator stack, so a
      // back press here would otherwise silently exit (and effectively
      // end) the delivery session with no warning. Intercept it and reuse
      // the same confirm-to-logout dialog as the explicit logout button.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _logout();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Deliveries',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                _auth.name,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
            ? RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                    Icon(
                      Icons.delivery_dining,
                      size: 64,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'No deliveries right now',
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'Pull down to refresh',
                        style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _orders.length,
                  itemBuilder: (_, i) =>
                      _orderCard(Map<String, dynamic>.from(_orders[i] as Map)),
                ),
              ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final orderId = (o['order_id'] ?? '').toString().isNotEmpty
        ? o['order_id']
        : (o['id'] ?? '');
    final displayId = (o['order_id'] ?? '').toString().isNotEmpty
        ? o['order_id']
        : '#${(o['id'] ?? '').toString().substring(0, 6)}';
    final status = o['order_status'] ?? '';
    final addr = Map<String, dynamic>.from(
      (o['delivery_address'] ?? {}) as Map,
    );
    final items = (o['items'] ?? []) as List;
    final total = (o['grand_total'] ?? o['total_amount'] ?? 0).toDouble();
    final phone = addr['phone']?.toString() ?? '';
    final name = addr['name']?.toString() ?? 'Customer';
    final outForDelivery = status == 'Out For Delivery';
    final busy = _busyId == orderId;

    final addrLine = [
      addr['house_no'],
      addr['street'],
      addr['landmark'],
      addr['area'],
      addr['city'],
      addr['pincode'],
    ].where((s) => s != null && s.toString().isNotEmpty).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  displayId,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: outForDelivery
                        ? AppColors.accentLight
                        : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: outForDelivery
                          ? AppColors.accent
                          : AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '₹${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        addrLine,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${items.length} item(s)',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                _actionBtn(
                  Icons.call,
                  'Call',
                  () => _call(phone),
                  AppColors.primary,
                ),
                const SizedBox(width: 8),
                _actionBtn(
                  Icons.directions,
                  'Navigate',
                  () => _navigate(addr),
                  AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy
                        ? null
                        : (outForDelivery
                              ? () => _delivered(orderId)
                              : () => _pickup(orderId)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: outForDelivery
                          ? AppColors.success
                          : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            outForDelivery ? 'Mark Delivered' : 'Pick Up',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    VoidCallback onTap,
    Color color,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
