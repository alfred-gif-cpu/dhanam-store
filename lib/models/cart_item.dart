class CartItem {
  final String productId;
  final String name;
  final String image;
  final String category;
  final double price;
  final double originalPrice;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.image,
    this.category = '',
    required this.price,
    this.originalPrice = 0,
    required this.quantity,
  });

  double get total => price * quantity;
  double get savings => originalPrice > price ? (originalPrice - price) * quantity : 0;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'image': image,
        'category': category,
        'price': price,
        'originalPrice': originalPrice,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      productId: json['productId'],
      name: json['name'],
      image: json['image'] ?? '',
      category: json['category'] ?? '',
      price: (json['price'] as num).toDouble(),
      originalPrice: (json['originalPrice'] ?? 0 as num).toDouble(),
      quantity: json['quantity'] as int,
    );
  }
}
