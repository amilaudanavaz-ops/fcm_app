import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category_model.dart';

class CategoryService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Fetch categories filtered by type ('expense' or 'income')
  Future<List<CategoryModel>> getCategories(String type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('categories')
        .select()
        .eq('user_id', userId)
        .eq('type', type)
        .order('name', ascending: true);

    final List<dynamic> data = response as List<dynamic>;
    return data.map((json) => CategoryModel.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Add a new category
  Future<CategoryModel?> addCategory(String name, String type) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final response = await _client
        .from('categories')
        .insert({
          'user_id': userId,
          'name': name.trim(),
          'type': type,
        })
        .select()
        .single();

    return CategoryModel.fromJson(response as Map<String, dynamic>);
  }

  /// Delete a category by ID
  Future<void> deleteCategory(String id) async {
    final parsedId = int.tryParse(id) ?? id;
    await _client.from('categories').delete().eq('id', parsedId);
  }
}