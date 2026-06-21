class Order {
  final String id;
  final String status;
  final double subtotal;
  final double gst;
  final double grandTotal;
  final List<OrderItem> items;
  final String createdAt;
  final Map<String, dynamic> address;

  Order({
    required this.id,
    required this.status,
    required this.subtotal,
    required this.gst,
    required this.grandTotal,
    required this.items,
    required this.createdAt,
    required this.address,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] ?? '',
      status: json['status'] ?? '',
      subtotal: (json['subtotal'] ?? 0).toDouble(),
      gst: (json['gst'] ?? 0).toDouble(),
      grandTotal: (json['grand_total'] ?? 0).toDouble(),
      items: (json['items'] as List? ?? []).map((e) => OrderItem.fromJson(e)).toList(),
      createdAt: json['created_at'] ?? '',
      address: json['address'] ?? {},
    );
  }
}

class OrderItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;

  OrderItem({required this.productId, required this.name, required this.price, required this.quantity});

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['product_id'] ?? '',
      name: json['name'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      quantity: json['quantity'] ?? 0,
    );
  }
}
