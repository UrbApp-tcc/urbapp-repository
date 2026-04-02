import 'package:supabase_flutter/supabase_flutter.dart';

class LookupOption {
  const LookupOption({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<LookupOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw Exception('Erro ao buscar cidades: ${e.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar cidades.');
    }
  }

  Future<List<LookupOption>> fetchCategories() async {
    try {
      final response = await _supabase
          .from('problem_categories')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw Exception('Erro ao buscar categorias: ${e.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar categorias.');
    }
  }

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
