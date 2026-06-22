import 'package:flutter/material.dart';
import '../../services/admin_auth_service.dart';
import '../../theme.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _auth = AdminAuthService();
  List<dynamic> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _auth.getStaff();
      if (mounted) setState(() { _staff = data['staff'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStaff() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? error;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add Delivery Staff', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Login email', prefixIcon: Icon(Icons.email_outlined))),
            const SizedBox(height: 12),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)', prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 12),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Password (min 6 chars)', prefixIcon: Icon(Icons.lock_outline))),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.length < 6) {
                  setSheet(() => error = 'Fill name, email, and a 6+ char password');
                  return;
                }
                try {
                  await _auth.createStaff(name: nameCtrl.text.trim(), email: emailCtrl.text.trim(), phone: phoneCtrl.text.trim(), password: passCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setSheet(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
              child: const Text('Create Account'),
            )),
          ]),
        ),
      ),
    );

    if (added == true) {
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff account created')));
    }
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Remove staff'),
      content: Text('Remove ${s['name']} (${s['email']})? They will no longer be able to log in.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (ok == true) {
      try { await _auth.deleteStaff(s['id']); _load(); } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Delivery Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Staff'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.badge_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No delivery staff yet', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Text('Tap "Add Staff" to create an employee login', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _staff.length,
                  itemBuilder: (_, i) {
                    final s = _staff[i] as Map<String, dynamic>;
                    final name = (s['name'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primarySurface,
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name.isNotEmpty ? name : 'Unnamed', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${s['email']}${(s['phone'] ?? '').toString().isNotEmpty ? ' • ${s['phone']}' : ''}', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.error), onPressed: () => _remove(s)),
                      ),
                    );
                  },
                ),
    );
  }
}
