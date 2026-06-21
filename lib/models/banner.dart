class HomeBanner {
  final String id;
  final String image;
  final String title;
  final String actionUrl;

  HomeBanner({required this.id, required this.image, required this.title, required this.actionUrl});

  factory HomeBanner.fromJson(Map<String, dynamic> json) {
    return HomeBanner(
      id: json['id'] ?? '',
      image: json['image'] ?? '',
      title: json['title'] ?? '',
      actionUrl: json['action_url'] ?? '',
    );
  }
}
