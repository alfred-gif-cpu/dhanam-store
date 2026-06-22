import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';

class AdminAuditLogsScreen extends StatefulWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  State<AdminAuditLogsScreen> createState() => _State();
}

class _State extends State<AdminAuditLogsScreen> {
  final AdminAuthService _auth = AdminAuthService();
  List<dynamic> _logs = [];
  bool _loading = true;
  int _total = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await _auth.getLogs();
      setState(() { _logs = data['logs']; _total = data['total']; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  IconData _actionIcon(String action) => switch (action) {
    'login' => Icons.login,
    'product_added' => Icons.add_box,
    'product_edited' => Icons.edit,
    'product_deleted' => Icons.delete,
    'order_status_updated' => Icons.local_shipping,
    'customer_blocked' => Icons.block,
    'customer_unblocked' => Icons.check_circle,
    'stock_updated' => Icons.inventory,
    'stock_received' => Icons.move_to_inbox,
    'password_changed' => Icons.lock,
    _ => Icons.info_outline,
  };

  Color _actionColor(String action) {
    if (action.contains('deleted') || action.contains('blocked')) return Colors.red;
    if (action.contains('added') || action.contains('received') || action.contains('unblocked')) return Colors.blue;
    if (action.contains('edited') || action.contains('updated')) return Colors.orange;
    if (action == 'login') return Colors.blue;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('Audit Logs ($_total)'), backgroundColor: Colors.indigo[800], foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(child: Text('No logs yet', style: TextStyle(color: Colors.grey[600])))
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  padding: const EdgeInsets.all(12), itemCount: _logs.length,
                  itemBuilder: (_, i) {
                    final log = _logs[i] as Map<String, dynamic>;
                    final action = log['action'] ?? '';
                    final color = _actionColor(action);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(_actionIcon(action), size: 18, color: color),
                        ),
                        title: Text(action.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if ((log['details'] ?? '').toString().isNotEmpty)
                            Text(log['details'], style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text('${log['admin_email']} • ${_formatTime(log['timestamp'] ?? '')}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ]),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  })),
    );
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }
}
