import 'package:supabase_flutter/supabase_flutter.dart';

class CityOption {
  const CityOption({
    required this.id,
    required this.name,
    required this.stateCode,
  });

  final int id;
  final String name;
  final String stateCode;

  String get stateAbbreviation => stateCode.toUpperCase();

  String get stateName => brazilianStateNames[stateCode] ?? stateAbbreviation;
}

const brazilianStateNames = <String, String>{
  'ac': 'Acre',
  'al': 'Alagoas',
  'ap': 'Amapá',
  'am': 'Amazonas',
  'ba': 'Bahia',
  'ce': 'Ceará',
  'df': 'Distrito Federal',
  'es': 'Espírito Santo',
  'go': 'Goiás',
  'ma': 'Maranhão',
  'mt': 'Mato Grosso',
  'ms': 'Mato Grosso do Sul',
  'mg': 'Minas Gerais',
  'pa': 'Pará',
  'pb': 'Paraíba',
  'pr': 'Paraná',
  'pe': 'Pernambuco',
  'pi': 'Piauí',
  'rj': 'Rio de Janeiro',
  'rn': 'Rio Grande do Norte',
  'rs': 'Rio Grande do Sul',
  'ro': 'Rondônia',
  'rr': 'Roraima',
  'sc': 'Santa Catarina',
  'sp': 'São Paulo',
  'se': 'Sergipe',
  'to': 'Tocantins',
};

class CityService {
  CityService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<CityOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name, state')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => CityOption(
              id: (item['id'] as num).toInt(),
              name: item['name'] as String,
              stateCode: item['state'] as String,
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
