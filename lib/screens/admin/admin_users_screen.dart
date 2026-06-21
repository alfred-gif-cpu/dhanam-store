import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AdminService _admin = AdminService();
  List<dynamic> _users = [];
  bool _loading = true;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _admin.getUsers();
      setState(() { _users = data['users']; _total = data['total']; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('Users ($_total)'), backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(child: Text('No users yet', style: TextStyle(color: Colors.grey[600])))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final u = _users[index] as Map<String, dynamic>;
                      final name = (u['name'] ?? '').toString();
                      final phone = (u['phone'] ?? '').toString();
                      final email = (u['email'] ?? '').toString();
                      final initials = name.isNotEmpty
                          ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
                          : phone.isNotEmpty ? phone.substring(phone.length - 2) : '??';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo[50],
                            child: Text(initials, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[700], fontSize: 14)),
                          ),
                          title: Text(name.isNotEmpty ? name : 'Unnamed User', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(phone, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                            if (email.isNotEmpty) Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          ]),
                          trailing: Text((u['created_at'] ?? '').toString().split('T').first,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
