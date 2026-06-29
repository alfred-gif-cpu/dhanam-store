import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/address.dart';
import '../../services/address_service.dart';
import '../../services/auth_service.dart';
import '../map_picker_screen.dart';

class AddressFormScreen extends StatefulWidget {
  final Address? address;
  const AddressFormScreen({super.key, this.address});

  @override
  State<AddressFormScreen> createState() => _State();
}

class _State extends State<AddressFormScreen> {
  final AddressService _svc = AddressService();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String _label = 'Home';
  double _lat = 0, _lng = 0;
  String _mapAddress = '';

  late TextEditingController _name, _phone, _houseNo, _street, _landmark, _area, _city, _state, _pincode;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    final a = widget.address;
    _name = TextEditingController(text: a?.name ?? '');
    _phone = TextEditingController(text: a?.phone ?? '');
    _houseNo = TextEditingController(text: a?.houseNo ?? '');
    _street = TextEditingController(text: a?.street ?? '');
    _landmark = TextEditingController(text: a?.landmark ?? '');
    _area = TextEditingController(text: a?.area ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _state = TextEditingController(text: a?.state ?? '');
    _pincode = TextEditingController(text: a?.pincode ?? '');
    _label = a?.label ?? 'Home';
    _lat = a?.latitude ?? 0;
    _lng = a?.longitude ?? 0;
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _houseNo.dispose(); _street.dispose();
    _landmark.dispose(); _area.dispose(); _city.dispose(); _state.dispose(); _pincode.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context, MaterialPageRoute(builder: (_) => MapPickerScreen(initialLat: _lat != 0 ? _lat : null, initialLng: _lng != 0 ? _lng : null)),
    );
    if (result != null) {
      setState(() {
        _lat = result['lat'];
        _lng = result['lng'];
        _mapAddress = result['address'] ?? '';
      });
      if (_street.text.isEmpty && _mapAddress.isNotEmpty) {
        _street.text = _mapAddress;
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'label': _label,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'house_no': _houseNo.text.trim(),
        'street': _street.text.trim(),
        'landmark': _landmark.text.trim(),
        'area': _area.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
      };
      if (_isEditing) {
        await _svc.updateAddress(widget.address!.id, data);
      } else {
        await _svc.addAddress(AuthService().userId, data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEditing ? 'Address updated' : 'Address added'),
          backgroundColor: Colors.blue, behavior: SnackBarBehavior.floating));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: Text(_isEditing ? 'Edit Address' : 'Add Address'), centerTitle: true, elevation: 0),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          // Label selector
          const Text('Address Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: ['Home', 'Work', 'Other'].map((l) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(l == 'Work' ? Icons.work_outlined : l == 'Other' ? Icons.location_on_outlined : Icons.home_outlined,
                    size: 16, color: _label == l ? Colors.blue[800] : Colors.grey[600]),
                const SizedBox(width: 4),
                Text(l),
              ]),
              selected: _label == l,
              onSelected: (_) => setState(() => _label = l),
              selectedColor: Colors.blue[100],
              labelStyle: TextStyle(color: _label == l ? Colors.blue[800] : Colors.grey[700], fontWeight: _label == l ? FontWeight.w600 : FontWeight.normal),
            ),
          )).toList()),
          const SizedBox(height: 20),

          // Map picker
          GestureDetector(
            onTap: _pickOnMap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _lat != 0 ? Colors.blue[50] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _lat != 0 ? Colors.blue[300]! : Colors.grey[300]!),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.map, color: Colors.blue[700], size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_lat != 0 ? 'Location Selected' : 'Pick Location on Map',
                      style: TextStyle(fontWeight: FontWeight.w600, color: _lat != 0 ? Colors.blue[800] : null)),
                  if (_lat != 0)
                    Text('${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}', style: TextStyle(fontSize: 12, color: Colors.blue[600]))
                  else
                    Text('Tap to select delivery location', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ])),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Contact
          _sectionTitle('Contact Details'),
          const SizedBox(height: 8),
          _buildField(_name, 'Full Name', Icons.person_outline, required: true),
          const SizedBox(height: 12),
          _buildField(_phone, 'Phone Number', Icons.phone_outlined, required: true,
              keyboard: TextInputType.phone, formatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 10),
          const SizedBox(height: 20),

          // Address
          _sectionTitle('Address Details'),
          const SizedBox(height: 8),
          _buildField(_houseNo, 'House / Flat / Floor No.', Icons.home_outlined, required: true),
          const SizedBox(height: 12),
          _buildField(_street, 'Street / Road / Area', Icons.signpost_outlined, required: true),
          const SizedBox(height: 12),
          _buildField(_landmark, 'Landmark (optional)', Icons.place_outlined),
          const SizedBox(height: 12),
          _buildField(_area, 'Area / Locality (optional)', Icons.map_outlined),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildField(_city, 'City', Icons.location_city_outlined, required: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildField(_state, 'State', Icons.flag_outlined, required: true)),
          ]),
          const SizedBox(height: 12),
          _buildField(_pincode, 'Pincode', Icons.pin_drop_outlined, required: true,
              keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 6),
          const SizedBox(height: 28),

          // Save button
          SizedBox(height: 54, child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox.shrink() : Icon(_isEditing ? Icons.save : Icons.add_location, size: 20),
            label: _saving
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEditing ? 'Update Address' : 'Save Address', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
          )),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title) => Row(children: [
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    const SizedBox(width: 4),
    const Text('*', style: TextStyle(color: Colors.red)),
  ]);

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.blue, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.red)),
      ),
    );
  }
}
