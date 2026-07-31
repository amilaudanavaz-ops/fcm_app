class CategoryModel {
  final String id;
  final String userId;
  final String name;
  final String type; // 'expense' or 'income'
  final String iconName;

  CategoryModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.iconName = 'category',
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'expense',
      iconName: json['icon_name']?.toString() ?? 'category',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'type': type,
      'icon_name': iconName,
    };
  }
}