import 'package:supabase_flutter/supabase_flutter.dart';

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> createPost({
    required int userId,
    required int cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    bool isAnonymous = false,
  }) async {
    try {
      await _supabase.from('posts').insert({
        'user_id': userId,
        'city_id': cityId,
        'category_id': categoryId,
        'title': title.trim(),
        'description': description.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'anonymity': isAnonymous,
        'status': 'open',
      });
    } on PostgrestException catch (e) {
      throw Exception('Erro ao criar post: ${e.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao criar post.');
    }
  }
}
