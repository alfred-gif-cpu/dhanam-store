import 'package:flutter/material.dart';
import '../../services/customer_service.dart';

class EditCustomerProfileScreen extends StatefulWidget {
  const EditCustomerProfileScreen({super.key});

  @override
  State<EditCustomerProfileScreen> createState() => _State();
}

class _State extends State<EditCustomerProfileScreen> {
  final CustomerService _cs = CustomerService();
  late TextEditingController _name, _email, _dob;
  String _gender = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _cs.name);
    _email = TextEditingController(text: _cs.email);
    _dob = TextEditingController(text: _cs.dateOfBirth);
    _gender = _cs.gender;
  }

  @override
  void dispose() { _name.dispose(); _email.dispose(); _dob.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _cs.updateProfile(name: _name.text.trim(), email: _email.text.trim(), gender: _gender, dob: _dob.text.trim());
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated'), backgroundColor: Colors.green)); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1950), lastDate: DateTime.now());
    if (picked != null) _dob.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Edit Profile'), centerTitle: true, elevation: 0),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: Stack(children: [
          CircleAvatar(radius: 48, backgroundColor: Colors.green[100],
            backgroundImage: _cs.profileImage.isNotEmpty ? NetworkImage(_cs.profileImage) : null,
            child: _cs.profileImage.isEmpty ? Icon(Icons.person, size: 48, color: Colors.green[700]) : null),
          Positioned(bottom: 0, right: 0, child: Container(
            padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
          )),
        ])),
        const SizedBox(height: 8),
        Center(child: Text(_cs.phone, style: TextStyle(color: Colors.grey[600]))),
        const SizedBox(height: 24),
        _field(_name, 'Full Name', Icons.person_outline),
        const SizedBox(height: 14),
        _field(_email, 'Email', Icons.email_outlined, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _pickDate,
          child: AbsorbPointer(child: _field(_dob, 'Date of Birth', Icons.cake_outlined)),
        ),
        const SizedBox(height: 14),
        Text('Gender', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
        const SizedBox(height: 8),
        Row(children: ['Male', 'Female', 'Other'].map((g) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(g), selected: _gender == g,
            onSelected: (_) => setState(() => _gender = g),
            selectedColor: Colors.green[100],
            labelStyle: TextStyle(color: _gender == g ? Colors.green[800] : Colors.grey[700], fontWeight: _gender == g ? FontWeight.w600 : FontWeight.normal),
          ),
        )).toList()),
        const SizedBox(height: 28),
        SizedBox(height: 54, child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
          child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        )),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType keyboard = TextInputType.text}) {
    return TextField(controller: c, keyboardType: keyboard, decoration: InputDecoration(
      labelText: label, prefixIcon: Icon(icon), filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.green, width: 2)),
    ));
  }
}
