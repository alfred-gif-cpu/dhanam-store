class Product {
  final String id;
  final String name;
  final String category;
  final String brand;
  final double price;
  final double originalPrice;
  final String image;
  final int stock;
  final String description;
  // `price` is already GST-inclusive at this item's own rate (e.g. 5% for
  // most groceries, 0% for some). gstRate is only needed to break the tax
  // portion out for display/invoicing — it must never be added again on
  // top of price.
  final double gstRate;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.brand,
    required this.price,
    required this.originalPrice,
    required this.image,
    required this.stock,
    required this.description,
    this.gstRate = 0,
  });

  int get discountPercent {
    if (originalPrice <= price || originalPrice == 0) return 0;
    return ((1 - price / originalPrice) * 100).round();
  }

  bool get hasDiscount => discountPercent > 0;
  bool get inStock => stock > 0;

  factory Product.fromJson(Map<String, dynamic> json) {
    final price = (json['price'] ?? 0).toDouble();
    final original = (json['original_price'] ?? json['mrp'] ?? 0).toDouble();
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      brand: json['brand'] ?? '',
      price: price,
      originalPrice: original > price ? original : price,
      image: json['image'] ?? '',
      stock: (json['stock'] ?? json['stock_quantity'] ?? 0).toInt(),
      description: json['description'] ?? '',
      gstRate: (json['gst'] ?? 0).toDouble(),
    );
  }
}
