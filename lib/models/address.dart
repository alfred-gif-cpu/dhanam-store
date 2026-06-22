class Address {
  final String id;
  final String customerId;
  final String label;
  final String name;
  final String phone;
  final String houseNo;
  final String street;
  final String landmark;
  final String area;
  final String city;
  final String state;
  final String pincode;
  final double latitude;
  final double longitude;
  final bool isDefault;

  Address({
    required this.id,
    this.customerId = '',
    required this.label,
    required this.name,
    required this.phone,
    required this.houseNo,
    required this.street,
    this.landmark = '',
    this.area = '',
    required this.city,
    required this.state,
    required this.pincode,
    this.latitude = 0,
    this.longitude = 0,
    this.isDefault = false,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      label: json['label'] ?? 'Home',
      name: json['name'] ?? json['full_name'] ?? '',
      phone: json['phone'] ?? '',
      houseNo: json['house_no'] ?? json['line1'] ?? '',
      street: json['street'] ?? json['line2'] ?? '',
      landmark: json['landmark'] ?? '',
      area: json['area'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      pincode: json['pincode'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      isDefault: json['is_default'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'name': name,
        'phone': phone,
        'house_no': houseNo,
        'street': street,
        'landmark': landmark,
        'area': area,
        'city': city,
        'state': state,
        'pincode': pincode,
        'latitude': latitude,
        'longitude': longitude,
      };

  String get fullName => name;
  String get shortAddress => '$houseNo, $street, $city - $pincode';
  String get fullAddress => [houseNo, street, landmark, area, city, state, pincode]
      .where((s) => s.isNotEmpty).join(', ');
  bool get hasCoordinates => latitude != 0 && longitude != 0;
}
