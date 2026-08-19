import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_auth_service.dart';

class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _State();
}

class _State extends State<AdminCustomersScreen> {
  // This screen built its own HttpClient and never set the Authorization
  // header, so every request came back 401. The response has no `customers`
  // key, the bare catch below swallowed the resulting error, and the screen
  // reported "No customers found" — with eleven customers in the database.
  // Going through AdminAuthService attaches the token and raises a failure
  // instead of rendering it as emptiness.
  final AdminAuthService _auth = AdminAuthService();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<dynamic> _customers = [];
  bool _loading = true;
  int _total = 0;
  int _page = 1;
  int _pages = 1;
  String _query = '';
  String _statusFilter = '';
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _auth.getCustomers(
          page: _page, q: _query, status: _statusFilter);
      setState(() {
        _customers = data['customers'] ?? [];
        _total = data['total'] ?? 0;
        _pages = data['pages'] ?? 1;
        _loading = false;
      });
    } catch (e) {
      // Reporting "no customers" when the request failed is worse than
      // reporting nothing: the shop reads it as having no customers.
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() { _query = v.trim(); _page = 1; });
      _load();
    });
  }

  /// The number to ring. A Google customer has no verified phone, so fall back
  /// to what they gave for delivery — and say so, because only one of the two
  /// proves anything.
  static String _phoneOf(Map c) {
    final verified = (c['phone'] ?? '').toString();
    if (verified.isNotEmpty) return verified;
    final contact = (c['contact_phone'] ?? '').toString();
    return contact.isEmpty ? '—' : '$contact (unverified)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('Customers ($_total)'), backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
      body: Column(children: [
        // Search
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TextField(
          controller: _search, onChanged: _onSearch,
          decoration: InputDecoration(
            hintText: 'Search by name, phone, email, ID...', prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _search.clear(); _onSearch(''); }) : null,
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
          ),
        )),
        // Filters
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          _chip('All', ''), _chip('Active', 'active'), _chip('Inactive', 'inactive'),
        ])),
        // List
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _customers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error != null
                            ? 'Could not load customers.\n$_error'
                            : 'No customers found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                    padding: const EdgeInsets.all(12), itemCount: _customers.length,
                    itemBuilder: (_, i) {
                      final c = _customers[i] as Map<String, dynamic>;
                      final active = c['is_active'] != false;
                      final name = (c['name'] ?? '').toString();
                      final initials = name.isNotEmpty ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase() : '??';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                          border: active ? null : Border.all(color: Colors.red.withValues(alpha: 0.3))),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: active ? Colors.indigo[50] : Colors.red[50],
                            child: Text(initials, style: TextStyle(fontWeight: FontWeight.bold, color: active ? Colors.indigo[700] : Colors.red, fontSize: 14))),
                          title: Row(children: [
                            Expanded(child: Text(name.isNotEmpty ? name : 'Unnamed', style: const TextStyle(fontWeight: FontWeight.w600))),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: (active ? Colors.blue : Colors.red).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text(active ? 'Active' : 'Blocked', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.blue : Colors.red))),
                          ]),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${_phoneOf(c)} • ${c['customer_id'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Row(children: [
                              Text('Wallet: ₹${(c['wallet_balance'] ?? 0).toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              const SizedBox(width: 8),
                              Text('Points: ${c['loyalty_points'] ?? 0}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ]),
                          ]),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              // `id` is the account's own id; customer_id is a
                              // legacy field that is not always present.
                              final id = (c['id'] ?? c['customer_id'] ?? '').toString();
                              try {
                                // The route is /unblock. This called /activate,
                                // which has never existed — masked because the
                                // request was unauthenticated and never reached
                                // a route at all.
                                if (action == 'block') await _auth.blockCustomer(id);
                                if (action == 'activate') await _auth.unblockCustomer(id);
                                await _load();
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Could not update customer: $e'),
                                    backgroundColor: Colors.red));
                              }
                            },
                            itemBuilder: (_) => [
                              if (active) const PopupMenuItem(value: 'block', child: Text('Block', style: TextStyle(color: Colors.red)))
                              else const PopupMenuItem(value: 'activate', child: Text('Activate', style: TextStyle(color: Colors.blue))),
                            ],
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      );
                    }))),
        // Pagination
        if (!_loading && _pages > 1)
          Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: _page > 1 ? () { _page--; _load(); } : null, icon: const Icon(Icons.chevron_left)),
            Text('Page $_page of $_pages', style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(onPressed: _page < _pages ? () { _page++; _load(); } : null, icon: const Icon(Icons.chevron_right)),
          ])),
      ]),
    );
  }

  Widget _chip(String label, String value) {
    final sel = _statusFilter == value;
    return Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.grey[700])),
      selected: sel, onSelected: (_) { _statusFilter = sel ? '' : value; _page = 1; _load(); },
      selectedColor: Colors.indigo, checkmarkColor: Colors.white, backgroundColor: Colors.white,
      side: BorderSide(color: sel ? Colors.indigo : Colors.grey[300]!),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ));
  }
}
