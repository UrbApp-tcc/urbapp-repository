import 'package:supabase_flutter/supabase_flutter.dart';

class CityOption {
  const CityOption({required this.id, required this.name});

  final int id;
  final String name;
}

class CityService {
  CityService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<CityOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => CityOption(
              id: (item['id'] as num).toInt(),
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar as cidades: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar as cidades.');
    }
  }

  Future<int?> fetchCurrentUserCityId() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select('city_id')
          .eq('id', userId)
          .maybeSingle();

      return (response?['city_id'] as num?)?.toInt();
    } on PostgrestException catch (error) {
      throw Exception(
        'Erro ao identificar a cidade do seu perfil: ${error.message}',
      );
    } catch (_) {
      throw Exception('Erro inesperado ao identificar a cidade do seu perfil.');
    }
  }
}
