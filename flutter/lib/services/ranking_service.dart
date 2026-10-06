import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_formatter.dart';

int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
double? _doubleOrNull(dynamic value) => (value as num?)?.toDouble();

/// Recorte do ranking de cidadãos. Os pontos seguem as regras de gamificação
/// existentes; o período só limita quais pontos contam.
enum RankingPeriod {
  month('month', 'Este mês'),
  all('all', 'Geral');

  const RankingPeriod(this.code, this.label);

  final String code;
  final String label;
}

/// Linha do ranking de cidadãos mais participativos (spec §22).
class CitizenRankingEntry {
  const CitizenRankingEntry({
    required this.position,
    required this.profileId,
    required this.name,
    this.avatarUrl,
    required this.level,
    required this.points,
    required this.publicReports,
  });

  factory CitizenRankingEntry.fromJson(Map<String, dynamic> json) {
    final fullName = (json['full_name'] as String?)?.trim() ?? '';
    return CitizenRankingEntry(
      position: _int(json['rank_position']),
      profileId: json['profile_id'] as String,
      name: fullName.isNotEmpty ? fullName : (json['username'] as String?)?.trim() ?? 'Cidadão',
      avatarUrl: json['avatar_url'] as String?,
      level: _int(json['current_level']).clamp(1, 99),
      points: _int(json['current_points']),
      publicReports: _int(json['posts_count']),
    );
  }

  final int position;
  final String profileId;
  final String name;
  final String? avatarUrl;
  final int level;

  /// Pontos do período consultado.
  final int points;
  final int publicReports;
}

/// Situação do usuário atual no ranking da cidade.
class ParticipationStanding {
  const ParticipationStanding({
    required this.points,
    required this.participants,
    this.position,
    this.pointsToNext,
    required this.eligible,
    this.reason,
  });

  factory ParticipationStanding.fromJson(Map<String, dynamic> json) => ParticipationStanding(
        points: _int(json['points']),
        participants: _int(json['participants']),
        position: (json['position'] as num?)?.toInt(),
        pointsToNext: (json['points_to_next'] as num?)?.toInt(),
        eligible: json['eligible'] == true,
        reason: json['reason'] as String?,
      );

  final int points;
  final int participants;
  final int? position;
  final int? pointsToNext;
  final bool eligible;

  /// `private` (perfil privado) ou `institutional` (perfil institucional).
  final String? reason;
}

/// Indicadores objetivos do ranking de cidades. Não existe score composto.
enum CityIndicator {
  resolutionRate('resolution_rate', 'Taxa de resolução'),
  resolutionTime('resolution_time', 'Tempo de resolução');

  const CityIndicator(this.code, this.label);

  final String code;
  final String label;
}

/// Cidade no ranking. Sem posição quando está abaixo da amostra mínima.
class CityRankingRow {
  const CityRankingRow({
    this.position,
    required this.cityId,
    required this.cityName,
    required this.stateCode,
    required this.eligible,
    required this.resolved,
    required this.resolutionRate,
    this.medianResolutionSeconds,
    required this.qualified,
    required this.minimumRequired,
  });

  factory CityRankingRow.fromJson(Map<String, dynamic> json) => CityRankingRow(
        position: (json['rank_position'] as num?)?.toInt(),
        cityId: _int(json['city_id']),
        cityName: json['city_name'] as String? ?? '',
        stateCode: (json['state'] as String? ?? '').toUpperCase(),
        eligible: _int(json['eligible_occurrences']),
        resolved: _int(json['resolved_occurrences']),
        resolutionRate: _doubleOrNull(json['resolution_rate']) ?? 0,
        medianResolutionSeconds: _doubleOrNull(json['median_resolution_seconds']),
        qualified: json['qualified'] == true,
        minimumRequired: _int(json['minimum_required']),
      );

  final int? position;
  final int cityId;
  final String cityName;
  final String stateCode;

  /// Ocorrências elegíveis criadas no período (denominador da taxa).
  final int eligible;

  /// Elegíveis com estado atual RESOLVIDO (numerador e amostra do tempo).
  final int resolved;
  final double resolutionRate;
  final double? medianResolutionSeconds;
  final bool qualified;
  final int minimumRequired;
}

/// Amostras mínimas, definidas no backend (`city_ranking_settings`).
class CityRankingSettings {
  const CityRankingSettings({required this.minOccurrencesForRate, required this.minResolvedForTime});

  final int minOccurrencesForRate;
  final int minResolvedForTime;
}

class RankingService {
  RankingService({SupabaseClient? supabase}) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<T> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw Exception(friendlyBackendMessage(error.message, fallback));
    }
  }

  Future<List<CitizenRankingEntry>> fetchCitizens(
    int cityId, {
    RankingPeriod period = RankingPeriod.all,
    int limit = 50,
    int offset = 0,
  }) {
    return _guard(() async {
      final rows = await _supabase.rpc('get_city_ranking', params: {
        'target_city_id': cityId,
        'page_size': limit,
        'page_offset': offset,
        'period': period.code,
      });
      return (rows as List).map((row) => CitizenRankingEntry.fromJson(Map<String, dynamic>.from(row as Map))).toList();
    }, 'Não foi possível carregar o ranking de cidadãos.');
  }

  Future<ParticipationStanding?> fetchStanding(int cityId, {RankingPeriod period = RankingPeriod.all}) {
    return _guard(() async {
      final result = await _supabase.rpc('get_participation_standing', params: {
        'target_city_id': cityId,
        'period': period.code,
      });
      if (result is! Map) return null;
      return ParticipationStanding.fromJson(Map<String, dynamic>.from(result));
    }, 'Não foi possível carregar sua posição.');
  }

  Future<List<CityRankingRow>> fetchCities({
    required CityIndicator indicator,
    RankingPeriod period = RankingPeriod.all,
    int limit = 50,
    int offset = 0,
  }) {
    return _guard(() async {
      final rows = await _supabase.rpc('get_city_resolution_ranking', params: {
        'indicator': indicator.code,
        'period': period.code,
        'page_size': limit,
        'page_offset': offset,
      });
      return (rows as List).map((row) => CityRankingRow.fromJson(Map<String, dynamic>.from(row as Map))).toList();
    }, 'Não foi possível carregar o ranking de cidades.');
  }

  Future<CityRankingSettings> fetchCitySettings() {
    return _guard(() async {
      final row = await _supabase
          .from('city_ranking_settings')
          .select('min_occurrences_for_rate, min_resolved_for_time')
          .single();
      return CityRankingSettings(
        minOccurrencesForRate: _int(row['min_occurrences_for_rate']),
        minResolvedForTime: _int(row['min_resolved_for_time']),
      );
    }, 'Não foi possível carregar as regras do ranking de cidades.');
  }
}
