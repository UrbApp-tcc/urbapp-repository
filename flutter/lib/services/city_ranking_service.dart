import 'package:supabase_flutter/supabase_flutter.dart';

class CityRankingCityOption {
  const CityRankingCityOption({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class CityRankingEntry {
  const CityRankingEntry({
    required this.rankPosition,
    required this.profileId,
    required this.fullName,
    required this.username,
    this.avatarUrl,
    required this.cityId,
    required this.cityName,
    required this.currentLevel,
    required this.currentXp,
    required this.currentPoints,
    required this.postsCount,
    required this.supportsReceived,
    required this.commentsReceived,
    required this.resolvedPostsCount,
    required this.rankingScore,
  });

  final int rankPosition;
  final String profileId;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final int cityId;
  final String cityName;
  final int currentLevel;
  final int currentXp;
  final int currentPoints;
  final int postsCount;
  final int supportsReceived;
  final int commentsReceived;
  final int resolvedPostsCount;
  final int rankingScore;
}

class CityRankingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<CityRankingCityOption>> fetchCities() async {
    try {
      final response = await _supabase.from('cities').select('id, name').order('name');

      return (response as List<dynamic>)
          .map(
            (item) => CityRankingCityOption(
              id: (item['id'] as num).toInt(),
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar cidades do ranking: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar cidades do ranking.');
    }
  }

  Future<int?> fetchCurrentUserCityId(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('city_id')
          .eq('id', userId)
          .maybeSingle();

      return (response?['city_id'] as num?)?.toInt();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao descobrir a cidade do seu perfil: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao descobrir a cidade do seu perfil.');
    }
  }

  Future<List<CityRankingEntry>> fetchCityRanking({
    required int cityId,
    int pageSize = 50,
    int pageOffset = 0,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_city_ranking',
        params: {
          'target_city_id': cityId,
          'page_size': pageSize,
          'page_offset': pageOffset,
        },
      );

      return (response as List<dynamic>)
          .map((item) => _mapEntry(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar ranking da cidade: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar ranking da cidade.');
    }
  }

  CityRankingEntry _mapEntry(Map<String, dynamic> data) {
    return CityRankingEntry(
      rankPosition: (data['rank_position'] as num?)?.toInt() ?? 0,
      profileId: data['profile_id'] as String,
      fullName: (data['full_name'] as String?)?.trim().isNotEmpty == true
          ? (data['full_name'] as String).trim()
          : (data['username'] as String?)?.trim() ?? 'Usuário',
      username: (data['username'] as String?)?.trim() ?? 'usuário',
      avatarUrl: data['avatar_url'] as String?,
      cityId: (data['city_id'] as num?)?.toInt() ?? 0,
      cityName: (data['city_name'] as String?)?.trim() ?? 'Cidade',
      currentLevel: (data['current_level'] as num?)?.toInt() ?? 1,
      currentXp: (data['current_xp'] as num?)?.toInt() ?? 0,
      currentPoints: (data['current_points'] as num?)?.toInt() ?? 0,
      postsCount: (data['posts_count'] as num?)?.toInt() ?? 0,
      supportsReceived: (data['supports_received'] as num?)?.toInt() ?? 0,
      commentsReceived: (data['comments_received'] as num?)?.toInt() ?? 0,
      resolvedPostsCount: (data['resolved_posts_count'] as num?)?.toInt() ?? 0,
      rankingScore: (data['ranking_score'] as num?)?.toInt() ?? 0,
    );
  }
}
